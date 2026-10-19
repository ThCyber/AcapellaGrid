import AVFoundation

/// Collects mic audio (with capture-clock timestamps) during calibration.
final class AudioCollector {
    struct Chunk {
        let start: Double
        let sampleRate: Double
        let samples: [Float]
    }

    private let lock = NSLock()
    private var chunks: [Chunk] = []

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer),
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32 else { return }
        let length = CMBlockBufferGetDataLength(block)
        var raw = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        raw.withUnsafeMutableBytes { bytes in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
        }
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let mono = channels == 1 ? raw : stride(from: 0, to: raw.count, by: channels).map { raw[$0] }
        let chunk = Chunk(start: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds,
                          sampleRate: asbd.mSampleRate, samples: mono)
        lock.lock()
        chunks.append(chunk)
        lock.unlock()
    }

    func snapshot() -> [Chunk] {
        lock.lock()
        defer { lock.unlock() }
        return chunks
    }
}

/// Finds how long after each scheduled click its sound (or the user's clap) arrives at the mic.
/// That round trip is exactly how late a singer's voice lands relative to the beat they hear,
/// so every take is shifted earlier by it.
enum LatencyAnalysis {
    struct Result: Equatable {
        var latency: Double
        var spread: Double
        var hits: Int
        var total: Int
    }

    static func measure(chunks: [AudioCollector.Chunk], clickTimes: [Double]) -> Result? {
        var offsets: [Double] = []
        for click in clickTimes {
            let window = samples(in: chunks, from: click - 0.15, to: click + 0.35)
            guard !window.isEmpty else { continue }
            let pre = window.filter { $0.time < click - 0.05 }
            let noise = pre.isEmpty ? 0 : pre.reduce(0) { $0 + abs($1.value) } / Float(pre.count)
            let peak = window.map { abs($0.value) }.max() ?? 0
            guard peak > max(0.01, noise * 6) else { continue }
            let threshold = max(peak * 0.35, noise * 4)
            if let onset = window.first(where: { $0.time >= click - 0.1 && abs($0.value) >= threshold }) {
                offsets.append(onset.time - click)
            }
        }
        guard offsets.count >= 3 else { return nil }
        let latency = median(offsets)
        let spread = median(offsets.map { abs($0 - latency) })
        return Result(latency: latency, spread: spread, hits: offsets.count, total: clickTimes.count)
    }

    private static func samples(in chunks: [AudioCollector.Chunk], from start: Double, to end: Double) -> [(time: Double, value: Float)] {
        var result: [(Double, Float)] = []
        for chunk in chunks {
            let chunkEnd = chunk.start + Double(chunk.samples.count) / chunk.sampleRate
            guard chunkEnd > start, chunk.start < end else { continue }
            let first = max(0, Int(((start - chunk.start) * chunk.sampleRate).rounded(.down)))
            let last = min(chunk.samples.count, Int(((end - chunk.start) * chunk.sampleRate).rounded(.up)))
            guard first < last else { continue }
            for i in first..<last {
                result.append((chunk.start + Double(i) / chunk.sampleRate, chunk.samples[i]))
            }
        }
        return result.sorted { $0.0 < $1.0 }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
