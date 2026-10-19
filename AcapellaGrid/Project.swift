import Foundation

struct TrackInfo: Codable, Equatable {
    var fileName: String
    /// Round-trip latency (click out → voice back in) measured/assumed when this take was recorded.
    /// The take is shifted earlier by this amount.
    var latencyComp: Double
    /// Seconds of lead-in recorded before bar 1 beat 1 (one bar at the tempo of the take).
    var leadIn: Double
    /// Manual fine-tuning from the Align sheet, in seconds (+ = later).
    var nudge: Double = 0
    var muted = false
    var volume: Float = 1
}

struct ProjectSettings: Codable, Equatable {
    var bpm: Double = 90
    var beatsPerBar = 4
    var countInBars = 1
    var clickDuringTake = true
    var clickDuringPlayback = false
    var clickVolume: Float = 0.8
    var mirrorVideo = true
    /// Measured with the Calibrate sheet. nil = use the audio engine's reported latency.
    var calibratedLatency: Double?
}

private struct ProjectFile: Codable {
    var settings: ProjectSettings
    var tracks: [TrackInfo?]
}

@MainActor
final class Project: ObservableObject {
    static let cellCount = 4

    @Published var settings = ProjectSettings() { didSet { save() } }
    @Published var tracks: [TrackInfo?] = Array(repeating: nil, count: cellCount) { didSet { save() } }

    let folder: URL
    private var isLoading = false

    init() {
        // `-ProjectFolder <path>` on the command line opens a different project (handy for demos).
        if let custom = UserDefaults.standard.string(forKey: "ProjectFolder") {
            folder = URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            folder = movies.appendingPathComponent("AcapellaGrid/Current Project", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    var secondsPerBeat: Double { 60 / min(max(settings.bpm, 30), 300) }
    var secondsPerBar: Double { secondsPerBeat * Double(settings.beatsPerBar) }
    var hasTracks: Bool { tracks.contains { $0 != nil } }

    func url(for track: TrackInfo) -> URL { folder.appendingPathComponent(track.fileName) }

    func makeTakeURL() -> URL {
        folder.appendingPathComponent("take-\(UUID().uuidString.prefix(8)).mov")
    }

    /// Where a take's media time 0 sits on the project timeline.
    /// Timeline 0 = start of the one-bar lead-in; bar 1 beat 1 = `secondsPerBar`.
    func timelineOffset(for track: TrackInfo) -> Double {
        (secondsPerBar - track.leadIn) + track.nudge - track.latencyComp
    }

    func replaceTrack(at index: Int, with track: TrackInfo?) {
        if let old = tracks[index], old.fileName != track?.fileName {
            try? FileManager.default.removeItem(at: url(for: old))
        }
        tracks[index] = track
    }

    func clearAll() {
        for i in 0..<Self.cellCount { replaceTrack(at: i, with: nil) }
    }

    // MARK: Persistence

    private var fileURL: URL { folder.appendingPathComponent("project.json") }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(ProjectFile.self, from: data) else { return }
        settings = file.settings
        var loaded = Array(file.tracks.prefix(Self.cellCount))
        loaded += Array(repeating: nil, count: Self.cellCount - loaded.count)
        tracks = loaded.map { track in
            guard let track, FileManager.default.fileExists(atPath: url(for: track).path) else { return nil }
            return track
        }
    }

    private func save() {
        guard !isLoading else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(ProjectFile(settings: settings, tracks: tracks)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
