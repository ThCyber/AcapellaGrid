// Generates a four-part demo project (cartoon singers + synthesized "doo" chords) for screenshots.
// Usage: swift Tools/make_demo.swift <output-folder>
import AVFoundation
import AppKit

let outFolder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "demo-project")
try? FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)

let bpm = 90.0, beatsPerBar = 4
let spb = 60 / bpm, bar = spb * Double(beatsPerBar)
let songBars = 4
let duration = bar * Double(songBars + 1) // lead-in bar + song
let sampleRate = 48_000.0
let width = 1280, height = 720, fps = 30

struct Voice {
    let name: String
    let colors: (UInt32, UInt32)
    let notes: [Int] // MIDI note per beat across the song; 0 = rest
}

// C – Am – F – G, one chord per bar.
let voices = [
    Voice(name: "SOPRANO", colors: (0xFF7A6B, 0xF2416B), notes: [76, 76, 79, 76, 76, 72, 72, 76, 77, 81, 77, 72, 74, 71, 74, 79]),
    Voice(name: "ALTO", colors: (0xFFC75A, 0xFF8F3D), notes: [72, 72, 72, 72, 69, 69, 69, 69, 69, 69, 69, 69, 71, 71, 67, 71]),
    Voice(name: "TENOR", colors: (0x4FE0C4, 0x1FA8B8), notes: [67, 0, 67, 0, 64, 0, 64, 0, 65, 0, 65, 0, 62, 0, 62, 0]),
    Voice(name: "BASS", colors: (0x7CB8FF, 0x5B6CFF), notes: [48, 0, 55, 0, 45, 0, 52, 0, 41, 0, 48, 0, 43, 0, 50, 0]),
]

func cg(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func noteLevel(_ voice: Voice, at t: Double) -> (freq: Double, env: Double)? {
    let songT = t - bar
    guard songT >= 0 else { return nil }
    let beat = Int(songT / spb)
    guard beat < voice.notes.count, voice.notes[beat] > 0 else { return nil }
    let inBeat = songT - Double(beat) * spb
    let env = min(1, inBeat / 0.03) * exp(-inBeat * 1.6)
    return (440 * pow(2, Double(voice.notes[beat] - 69) / 12), env)
}

func writeAudio(_ voice: Voice, to url: URL) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    let frames = AVAudioFrameCount(duration * sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let data = buffer.floatChannelData![0]
    var phase = 0.0
    for i in 0..<Int(frames) {
        let t = Double(i) / sampleRate
        // Hold the previous note through a rest so tenor/bass sound like half notes.
        var note = noteLevel(voice, at: t)
        if note == nil, t >= bar {
            let beat = Int((t - bar) / spb)
            if beat > 0, beat < voice.notes.count, voice.notes[beat] == 0 {
                note = noteLevel(voice, at: t - spb)
            }
        }
        guard let (freq, env) = note else { data[i] = 0; continue }
        let vibrato = 1 + 0.004 * sin(2 * .pi * 5.2 * t)
        phase += 2 * .pi * freq * vibrato / sampleRate
        let tone = sin(phase) + 0.35 * sin(2 * phase) + 0.12 * sin(3 * phase)
        data[i] = Float(0.22 * env * tone)
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

func drawFrame(_ voice: Voice, t: Double, into ctx: CGContext) {
    let w = CGFloat(width), h = CGFloat(height)
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [cg(voice.colors.0), cg(voice.colors.1)] as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

    let singing = noteLevel(voice, at: t)?.env ?? 0
    let beatPhase = t / spb - floor(t / spb)
    let bob = CGFloat(sin(beatPhase * .pi)) * 10

    // Shoulders.
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
    ctx.addEllipse(in: CGRect(x: w / 2 - 300, y: -260 + bob, width: 600, height: 520))
    ctx.fillPath()
    // Head.
    let head = CGRect(x: w / 2 - 125, y: 250 + bob, width: 250, height: 280)
    ctx.addEllipse(in: head)
    ctx.fillPath()
    // Eyes.
    ctx.setFillColor(cg(0x1A123D))
    for dx in [-48.0, 48.0] {
        ctx.addEllipse(in: CGRect(x: head.midX + CGFloat(dx) - 13, y: head.midY + 30, width: 26, height: 34))
    }
    ctx.fillPath()
    // Mouth opens while singing.
    let open = 10 + CGFloat(singing) * 46
    ctx.addEllipse(in: CGRect(x: head.midX - 30, y: head.midY - 55 - open / 2, width: 60, height: open))
    ctx.fillPath()

    // Label.
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 64, weight: .heavy),
        .foregroundColor: NSColor(white: 1, alpha: 0.95),
        .kern: 6,
    ]
    let label = NSAttributedString(string: voice.name, attributes: attributes)
    let line = CTLineCreateWithAttributedString(label)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    ctx.textPosition = CGPoint(x: 60, y: h - 60 - bounds.height)
    CTLineDraw(line, ctx)
}

func writeVideo(_ voice: Voice, to url: URL) async throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let frameCount = Int(duration * Double(fps))
    for f in 0..<frameCount {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
        let buffer = pb!
        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        drawFrame(voice, t: Double(f) / Double(fps), into: ctx)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    await writer.finishWriting()
}

func mux(video: URL, audio: URL, to url: URL) async throws {
    let composition = AVMutableComposition()
    let v = AVURLAsset(url: video), a = AVURLAsset(url: audio)
    let vt = try await v.loadTracks(withMediaType: .video)[0]
    let at = try await a.loadTracks(withMediaType: .audio)[0]
    let range = CMTimeRange(start: .zero, duration: try await v.load(.duration))
    try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: vt, at: .zero)
    try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: at, at: .zero)
    try? FileManager.default.removeItem(at: url)
    let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
    try await export.export(to: url, as: .mov)
}

var tracks: [[String: Any]] = []
for (i, voice) in voices.enumerated() {
    let tmpVideo = outFolder.appendingPathComponent("v\(i).mov"), tmpAudio = outFolder.appendingPathComponent("a\(i).caf")
    try writeAudio(voice, to: tmpAudio)
    try await writeVideo(voice, to: tmpVideo)
    let name = "demo-\(voice.name.lowercased()).mov"
    try await mux(video: tmpVideo, audio: tmpAudio, to: outFolder.appendingPathComponent(name))
    try? FileManager.default.removeItem(at: tmpVideo)
    try? FileManager.default.removeItem(at: tmpAudio)
    tracks.append(["fileName": name, "latencyComp": 0, "leadIn": bar, "nudge": 0, "muted": false, "volume": 1])
    print("wrote \(name)")
}
let project: [String: Any] = [
    "settings": ["bpm": bpm, "beatsPerBar": beatsPerBar, "countInBars": 1, "clickDuringTake": true,
                 "clickDuringPlayback": false, "clickVolume": 0.8, "mirrorVideo": false, "calibratedLatency": 0.038],
    "tracks": tracks,
]
try JSONSerialization.data(withJSONObject: project, options: .prettyPrinted).write(to: outFolder.appendingPathComponent("project.json"))
print("done")
