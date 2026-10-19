import AVFoundation

enum RecorderError: LocalizedError {
    case noCamera, noMicrophone, cannotAdd(String), writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCamera: "No camera was found."
        case .noMicrophone: "No microphone was found."
        case .cannotAdd(let what): "Could not attach the \(what) to the capture session."
        case .writerFailed(let reason): "Could not start recording: \(reason)"
        }
    }
}

/// Camera + mic capture. Instead of "start recording now", a take starts at an exact
/// host time: every sample buffer carries a capture-clock timestamp, so the file's
/// time 0 is pinned to the same instant the backing tracks start playing.
final class CaptureRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "AcapellaGrid.capture")

    // State below is only touched on `queue`.
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStart = CMTime.invalid
    private var videoSize = CMVideoDimensions(width: 1280, height: 720)
    private var audioTap: ((CMSampleBuffer) -> Void)?

    static func requestAccess() async -> Bool {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        let audio = await AVCaptureDevice.requestAccess(for: .audio)
        return video && audio
    }

    func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }

        guard let camera = AVCaptureDevice.default(for: .video) else { throw RecorderError.noCamera }
        guard let mic = AVCaptureDevice.default(for: .audio) else { throw RecorderError.noMicrophone }
        for (device, name) in [(camera, "camera"), (mic, "microphone")] {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw RecorderError.cannotAdd(name) }
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(videoOutput) else { throw RecorderError.cannotAdd("video output") }
        session.addOutput(videoOutput)

        // Mono float PCM: easy to analyse for calibration, and the writer encodes it to AAC.
        audioOutput.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        audioOutput.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(audioOutput) else { throw RecorderError.cannotAdd("audio output") }
        session.addOutput(audioOutput)
    }

    func startRunning() {
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    /// The clock that sample-buffer timestamps are expressed in.
    var clock: CMClock { session.synchronizationClock ?? CMClockGetHostTimeClock() }

    func captureTime(hostTime: UInt64) -> CMTime {
        CMSyncConvertTime(HostTime.cmTime(hostTime), from: CMClockGetHostTimeClock(), to: clock)
    }

    /// Receives every mic buffer (on the capture queue). Used for latency calibration.
    func setAudioTap(_ tap: ((CMSampleBuffer) -> Void)?) {
        queue.async { self.audioTap = tap }
    }

    /// Starts writing a take whose time 0 is exactly `hostTime`.
    func startRecording(to url: URL, atHostTime hostTime: UInt64) throws {
        try? FileManager.default.removeItem(at: url)
        let start = captureTime(hostTime: hostTime)
        try queue.sync {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(videoSize.width),
                AVVideoHeightKey: Int(videoSize.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000],
            ])
            video.expectsMediaDataInRealTime = true
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 192_000,
            ])
            audio.expectsMediaDataInRealTime = true
            guard writer.canAdd(video), writer.canAdd(audio) else { throw RecorderError.writerFailed("unsupported format") }
            writer.add(video)
            writer.add(audio)
            guard writer.startWriting() else {
                throw RecorderError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
            }
            writer.startSession(atSourceTime: start)
            self.writer = writer
            self.videoInput = video
            self.audioInput = audio
            self.sessionStart = start
        }
    }

    func stopRecording() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let writer = self.writer else { return continuation.resume(returning: false) }
                self.writer = nil
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                writer.finishWriting { continuation.resume(returning: writer.status == .completed) }
            }
        }
    }

    func cancelRecording() {
        queue.sync {
            writer?.cancelWriting()
            writer = nil
        }
    }

    // MARK: Sample buffers

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let isAudio = output === audioOutput
        if isAudio {
            audioTap?(sampleBuffer)
        } else if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            videoSize = CMVideoFormatDescriptionGetDimensions(format)
        }

        guard let writer, writer.status == .writing else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if isAudio {
            let end = pts + CMSampleBufferGetDuration(sampleBuffer)
            if end > sessionStart, let audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            }
        } else {
            // Keep the frame just before the start so the first frame isn't blank.
            if pts >= sessionStart - CMTime(value: 1, timescale: 20), let videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        }
    }
}
