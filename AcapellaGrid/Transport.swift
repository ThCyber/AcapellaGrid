import AVFoundation
import AppKit

enum TransportState: Equatable {
    case idle
    case countIn(Int)
    case recording(Int)
    case playing
    case calibrating

    var activeCell: Int? {
        switch self {
        case .countIn(let cell), .recording(let cell): cell
        default: nil
        }
    }
}

enum CameraStatus: Equatable {
    case unknown, ready, denied
    case failed(String)
}

/// Coordinates the metronome, backing-track player and recorder on one host-time timeline.
///
/// Timeline layout (same for recording, playback and export):
///
///     count-in clicks …  | lead-in bar | bar 1 | bar 2 | …
///                        ^ timeline 0  ^ songStart (beat 0)
///
/// When recording, the recorder's file time 0, the backing composition's time 0 and
/// the metronome's lead-in bar are all scheduled at the same future host time.
@MainActor
final class Transport: ObservableObject {
    @Published private(set) var state: TransportState = .idle
    @Published private(set) var songStart: UInt64?
    @Published private(set) var cameraStatus: CameraStatus = .unknown
    @Published private(set) var exportProgress: Double?
    @Published private(set) var lastCalibration: LatencyAnalysis.Result?
    @Published var alertMessage: String?

    let player = AVPlayer()
    let recorder = CaptureRecorder()
    let metronome = Metronome()
    let project: Project

    private var takeURL: URL?
    private var takeLeadIn = 0.0
    private var takeLatency = 0.0
    private var visualLatency = 0.0
    private var endObserver: NSObjectProtocol?
    private var countInTask: Task<Void, Never>?

    init(project: Project) {
        self.project = project
        player.automaticallyWaitsToMinimizeStalling = false
    }

    // MARK: Latency

    var estimatedLatency: Double { metronome.outputLatency + 0.010 }
    var latencyCompensation: Double { project.settings.calibratedLatency ?? estimatedLatency }
    var isCalibrated: Bool { project.settings.calibratedLatency != nil }

    // MARK: Setup

    func setup() async {
        guard cameraStatus == .unknown else { return }
        guard await CaptureRecorder.requestAccess() else {
            cameraStatus = .denied
            return
        }
        do {
            try recorder.configure()
            recorder.startRunning()
            cameraStatus = .ready
        } catch {
            cameraStatus = .failed(error.localizedDescription)
        }
        await refreshPlayer()
    }

    /// Continuous beat position for the visual metronome: 0 = bar 1 beat 1, negative = count-in.
    /// Shifted by the output latency so the flash lines up with the click you hear.
    func beatPosition(atHostTime now: UInt64) -> Double? {
        guard let songStart else { return nil }
        return (HostTime.delta(now, songStart) - visualLatency) / project.secondsPerBeat
    }

    // MARK: Grid actions

    func cellTapped(_ cell: Int) {
        switch state {
        case .idle:
            if project.tracks[cell] == nil { Task { await record(cell: cell) } }
        case .countIn(let active), .recording(let active):
            if active == cell { Task { await stopRecording() } }
        default:
            break
        }
    }

    func togglePlay() {
        switch state {
        case .idle: Task { await play() }
        case .playing: stopPlayback()
        case .countIn, .recording: Task { await stopRecording() }
        case .calibrating: break
        }
    }

    // MARK: Recording

    func record(cell: Int) async {
        guard state == .idle else { return }
        guard cameraStatus == .ready else {
            alertMessage = "Camera and microphone access is needed to record. Enable it in System Settings › Privacy & Security."
            return
        }
        state = .countIn(cell)

        // Everything except the cell being (re)recorded plays along.
        await loadComposition(cells: (0..<Project.cellCount).filter { $0 != cell })

        let settings = project.settings
        let spb = project.secondsPerBeat
        let bar = project.secondsPerBar
        let countInBeats = max(1, settings.countInBars) * settings.beatsPerBar
        // Leave 350 ms for everything to get ready, then the count-in, then bar 1.
        let start = HostTime.now + HostTime.ticks(0.35 + Double(countInBeats) * spb)
        let timelineStart = HostTime.offset(start, by: -bar)

        do {
            let url = project.makeTakeURL()
            try recorder.startRecording(to: url, atHostTime: timelineStart)
            takeURL = url
            takeLeadIn = bar
            takeLatency = latencyCompensation
            metronome.volume = settings.clickVolume
            try metronome.start(songStart: start, secondsPerBeat: spb, beatsPerBar: settings.beatsPerBar,
                                firstBeat: -countInBeats, lastBeat: settings.clickDuringTake ? nil : -1)
        } catch {
            recorder.cancelRecording()
            metronome.stop()
            state = .idle
            alertMessage = error.localizedDescription
            return
        }

        if player.currentItem != nil {
            player.setRate(1, time: .zero, atHostTime: HostTime.cmTime(timelineStart))
        }
        visualLatency = metronome.outputLatency
        songStart = start

        countInTask = Task { [weak self] in
            let wait = HostTime.delta(start, HostTime.now)
            try? await Task.sleep(nanoseconds: UInt64(max(0, wait) * 1_000_000_000))
            guard let self, !Task.isCancelled, self.state == .countIn(cell) else { return }
            self.state = .recording(cell)
        }
    }

    func stopRecording() async {
        guard let cell = state.activeCell else { return }
        let reachedBarOne = state == .recording(cell)
        countInTask?.cancel()
        metronome.stop()
        player.pause()

        if reachedBarOne, await recorder.stopRecording(), let url = takeURL {
            project.replaceTrack(at: cell, with: TrackInfo(fileName: url.lastPathComponent,
                                                           latencyComp: takeLatency, leadIn: takeLeadIn))
        } else {
            // Stopped during the count-in: throw the take away.
            recorder.cancelRecording()
            if let takeURL { try? FileManager.default.removeItem(at: takeURL) }
        }
        takeURL = nil
        songStart = nil
        state = .idle
        await refreshPlayer()
    }

    // MARK: Playback

    func play() async {
        guard state == .idle, project.hasTracks else { return }
        state = .playing
        await loadComposition(cells: Array(0..<Project.cellCount))
        guard state == .playing, player.currentItem != nil else {
            state = .idle
            return
        }
        let settings = project.settings
        let timelineStart = HostTime.now + HostTime.ticks(0.3)
        let start = HostTime.offset(timelineStart, by: project.secondsPerBar)
        player.setRate(1, time: .zero, atHostTime: HostTime.cmTime(timelineStart))
        if settings.clickDuringPlayback {
            metronome.volume = settings.clickVolume
            try? metronome.start(songStart: start, secondsPerBeat: project.secondsPerBeat,
                                 beatsPerBar: settings.beatsPerBar, firstBeat: -settings.beatsPerBar, lastBeat: nil)
        }
        visualLatency = metronome.outputLatency
        songStart = start
    }

    func stopPlayback() {
        guard state == .playing else { return }
        metronome.stop()
        player.pause()
        player.seek(to: .zero)
        songStart = nil
        state = .idle
    }

    /// Rebuilds the full grid so the idle view shows every take's first frame.
    func refreshPlayer() async {
        guard state == .idle else { return }
        await loadComposition(cells: Array(0..<Project.cellCount))
        await player.seek(to: .zero)
    }

    private func compositionInputs(cells: [Int]) -> [CompositionBuilder.Input] {
        cells.compactMap { cell in
            guard let track = project.tracks[cell] else { return nil }
            return CompositionBuilder.Input(cell: cell, url: project.url(for: track),
                                            offset: project.timelineOffset(for: track),
                                            volume: track.muted ? 0 : track.volume)
        }
    }

    private func loadComposition(cells: [Int]) async {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        let inputs = compositionInputs(cells: cells)
        guard !inputs.isEmpty else {
            player.replaceCurrentItem(with: nil)
            return
        }
        do {
            let grid = try await CompositionBuilder.build(inputs, mirror: project.settings.mirrorVideo)
            let item = grid.makePlayerItem()
            player.replaceCurrentItem(with: item)
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.stopPlayback() }
            }
            for _ in 0..<150 where item.status == .unknown {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            if item.status == .readyToPlay {
                _ = await player.preroll(atRate: 1)
            } else {
                player.replaceCurrentItem(with: nil)
            }
        } catch {
            player.replaceCurrentItem(with: nil)
            alertMessage = "Couldn't load the takes: \(error.localizedDescription)"
        }
    }

    // MARK: Calibration

    func calibrate() async {
        guard state == .idle, cameraStatus == .ready else { return }
        state = .calibrating
        let collector = AudioCollector()
        recorder.setAudioTap { collector.append($0) }

        let clickCount = 10, spacing = 0.5
        let first = HostTime.now + HostTime.ticks(0.8)
        let hostTimes = (0..<clickCount).map { HostTime.offset(first, by: Double($0) * spacing) }
        visualLatency = metronome.outputLatency
        metronome.volume = 1
        do {
            try metronome.playClicks(atHostTimes: hostTimes)
        } catch {
            recorder.setAudioTap(nil)
            state = .idle
            alertMessage = error.localizedDescription
            return
        }
        try? await Task.sleep(nanoseconds: UInt64((0.8 + Double(clickCount) * spacing + 0.4) * 1_000_000_000))
        recorder.setAudioTap(nil)
        metronome.stop()

        let clickTimes = hostTimes.map { recorder.captureTime(hostTime: $0).seconds }
        state = .idle
        if let result = LatencyAnalysis.measure(chunks: collector.snapshot(), clickTimes: clickTimes) {
            lastCalibration = result
            project.settings.calibratedLatency = max(0, result.latency)
        } else {
            alertMessage = "The microphone didn't pick up the clicks clearly. Turn the volume up (or clap louder) and try again."
        }
    }

    // MARK: Export

    func export(to url: URL) async {
        let inputs = compositionInputs(cells: Array(0..<Project.cellCount))
        guard !inputs.isEmpty else { return }
        do {
            let grid = try await CompositionBuilder.build(inputs, mirror: project.settings.mirrorVideo)
            guard let session = AVAssetExportSession(asset: grid.composition, presetName: AVAssetExportPreset1920x1080) else {
                alertMessage = "Export isn't available on this Mac."
                return
            }
            try? FileManager.default.removeItem(at: url)
            session.videoComposition = grid.videoComposition
            session.audioMix = grid.audioMix
            session.outputURL = url
            session.outputFileType = .mp4
            exportProgress = 0
            let poll = Task { [weak self] in
                while !Task.isCancelled {
                    self?.exportProgress = Double(session.progress)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
            poll.cancel()
            exportProgress = nil
            if session.status == .completed {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                alertMessage = "Export failed: \(session.error?.localizedDescription ?? "unknown error")"
            }
        } catch {
            exportProgress = nil
            alertMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
