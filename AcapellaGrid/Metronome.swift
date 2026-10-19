import AVFoundation

/// Sample-accurate click track. Every click is scheduled at an absolute host time
/// derived from the song's start, so it can never drift against the backing tracks.
final class Metronome {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private lazy var accentClick = makeClick(frequency: 1760, gain: 0.9)
    private lazy var beatClick = makeClick(frequency: 1175, gain: 0.55)

    private var timer: DispatchSourceTimer?
    private var songStart: UInt64 = 0
    private var secondsPerBeat = 0.5
    private var beatsPerBar = 4
    private var nextBeat = 0
    private var lastBeat: Int?

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    var volume: Float {
        get { node.volume }
        set { node.volume = newValue }
    }

    /// What the output device reports as its latency (buffer + device + safety offset).
    var outputLatency: Double { engine.outputNode.presentationLatency }

    /// Clicks beat `b` at `songStart + b * secondsPerBeat`. Negative beats are the count-in.
    func start(songStart: UInt64, secondsPerBeat: Double, beatsPerBar: Int, firstBeat: Int, lastBeat: Int?) throws {
        stop()
        try ensureRunning()
        self.songStart = songStart
        self.secondsPerBeat = secondsPerBeat
        self.beatsPerBar = beatsPerBar
        self.nextBeat = firstBeat
        self.lastBeat = lastBeat
        fill()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [weak self] in self?.fill() }
        t.resume()
        timer = t
    }

    func playClicks(atHostTimes times: [UInt64]) throws {
        stop()
        try ensureRunning()
        for t in times {
            node.scheduleBuffer(accentClick, at: AVAudioTime(hostTime: t))
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if engine.isRunning { node.stop() }
    }

    private func ensureRunning() throws {
        if !engine.isRunning { try engine.start() }
        node.stop()
        node.play()
    }

    /// Schedules clicks up to half a second ahead; called every 100 ms.
    private func fill() {
        let now = HostTime.now
        let horizon = now + HostTime.ticks(0.5)
        while lastBeat.map({ nextBeat <= $0 }) ?? true {
            let t = HostTime.offset(songStart, by: Double(nextBeat) * secondsPerBeat)
            guard t < horizon else { break }
            if t > now {
                let isDownbeat = ((nextBeat % beatsPerBar) + beatsPerBar) % beatsPerBar == 0
                node.scheduleBuffer(isDownbeat ? accentClick : beatClick, at: AVAudioTime(hostTime: t))
            }
            nextBeat += 1
        }
        if let lastBeat, nextBeat > lastBeat {
            timer?.cancel()
            timer = nil
        }
    }

    private func makeClick(frequency: Double, gain: Float) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(sampleRate * 0.05)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            samples[i] = gain * Float(sin(2 * .pi * frequency * t) * exp(-t * 90))
        }
        return buffer
    }
}
