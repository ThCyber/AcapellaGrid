import AVFoundation
import SwiftUI

/// Loads a 1 ms-resolution peak envelope for each take.
@MainActor
final class WaveformStore: ObservableObject {
    @Published private(set) var envelopes: [String: [Float]] = [:]
    private var loading: Set<String> = []

    func load(_ url: URL) {
        let key = url.lastPathComponent
        guard envelopes[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        Task.detached(priority: .userInitiated) {
            let envelope = (try? await Self.readEnvelope(url)) ?? []
            await MainActor.run {
                self.envelopes[key] = envelope
                self.loading.remove(key)
            }
        }
    }

    nonisolated static func readEnvelope(_ url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return [] }

        var envelope: [Float] = []
        var peak: Float = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            samples.withUnsafeMutableBytes { bytes in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: bytes.baseAddress!)
            }
            for sample in samples {
                peak = max(peak, abs(sample))
                count += 1
                if count == 48 {
                    envelope.append(peak)
                    peak = 0
                    count = 0
                }
            }
        }
        let maximum = envelope.max() ?? 0
        return maximum > 0 ? envelope.map { $0 / maximum } : envelope
    }
}

/// Every take drawn against the shared beat grid, with nudge controls.
struct AlignmentView: View {
    @EnvironmentObject private var project: Project
    @Environment(\.dismiss) private var dismiss
    @StateObject private var waveforms = WaveformStore()
    @State private var visibleBars = 2
    @State private var startBar = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Align Tracks").font(.title2.bold())
            Text("Each lane is a take's waveform on the shared beat grid. Bold lines are bar lines; the red line is bar 1, beat 1. If a take's consonants and attacks sit consistently ahead of or behind the lines, nudge it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 24) {
                Stepper("Showing \(visibleBars) bar\(visibleBars == 1 ? "" : "s")", value: $visibleBars, in: 1...16)
                Stepper(startBar == 0 ? "From the lead-in" : "From bar \(startBar)", value: $startBar, in: 0...200)
            }

            ForEach(0..<Project.cellCount, id: \.self) { index in
                lane(index)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 940)
        .onAppear {
            for track in project.tracks.compactMap({ $0 }) { waveforms.load(project.url(for: track)) }
        }
    }

    @ViewBuilder
    private func lane(_ index: Int) -> some View {
        HStack(spacing: 12) {
            Text("Track \(index + 1)")
                .font(.headline)
                .frame(width: 70, alignment: .leading)

            if let track = project.tracks[index] {
                WaveformLane(envelope: waveforms.envelopes[track.fileName],
                             offset: project.timelineOffset(for: track),
                             viewStart: Double(startBar) * project.secondsPerBar,
                             viewDuration: Double(visibleBars) * project.secondsPerBar,
                             secondsPerBeat: project.secondsPerBeat,
                             beatsPerBar: project.settings.beatsPerBar)
                    .frame(height: 76)

                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        nudgeButton("−10", index, -0.010)
                        nudgeButton("−1", index, -0.001)
                        nudgeButton("+1", index, 0.001)
                        nudgeButton("+10", index, 0.010)
                    }
                    HStack {
                        Text(String(format: "%+.0f ms", track.nudge * 1000))
                            .monospacedDigit()
                            .foregroundStyle(track.nudge == 0 ? .secondary : .primary)
                        Spacer()
                        Button("Reset") { project.tracks[index]?.nudge = 0 }
                            .controlSize(.small)
                            .disabled(track.nudge == 0)
                    }
                }
                .frame(width: 190)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(Text("Empty").foregroundStyle(.secondary))
                    .frame(height: 76)
                Color.clear.frame(width: 190)
            }
        }
    }

    private func nudgeButton(_ title: String, _ index: Int, _ amount: Double) -> some View {
        Button(title) { project.tracks[index]?.nudge += amount }
            .controlSize(.small)
            .frame(minWidth: 40)
    }
}

private struct WaveformLane: View {
    let envelope: [Float]?
    let offset: Double
    let viewStart: Double
    let viewDuration: Double
    let secondsPerBeat: Double
    let beatsPerBar: Int

    var body: some View {
        Canvas { context, size in
            let bar = secondsPerBeat * Double(beatsPerBar)
            func x(_ t: Double) -> CGFloat { CGFloat((t - viewStart) / viewDuration) * size.width }

            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                         with: .color(Color.secondary.opacity(0.08)))
            if viewStart < bar {
                context.fill(Path(CGRect(x: 0, y: 0, width: x(bar), height: size.height)),
                             with: .color(Color.orange.opacity(0.08)))
            }

            let firstBeat = Int((viewStart / secondsPerBeat).rounded(.down))
            let lastBeat = Int(((viewStart + viewDuration) / secondsPerBeat).rounded(.up))
            for beat in firstBeat...lastBeat {
                let lineX = x(Double(beat) * secondsPerBeat)
                let isBar = beat % beatsPerBar == 0
                let isSongStart = beat == beatsPerBar
                var line = Path()
                line.move(to: CGPoint(x: lineX, y: 0))
                line.addLine(to: CGPoint(x: lineX, y: size.height))
                context.stroke(line, with: .color(isSongStart ? .red : Color.primary.opacity(isBar ? 0.45 : 0.15)),
                               lineWidth: isSongStart ? 2 : (isBar ? 1.5 : 1))
            }

            guard let envelope, !envelope.isEmpty else { return }
            let mid = size.height / 2
            var wave = Path()
            let columns = max(1, Int(size.width))
            for column in 0..<columns {
                let t0 = viewStart + Double(column) / Double(columns) * viewDuration - offset
                let t1 = viewStart + Double(column + 1) / Double(columns) * viewDuration - offset
                let lo = max(0, Int(t0 * 1000)), hi = min(envelope.count, Int(t1 * 1000) + 1)
                guard lo < hi else { continue }
                let peak = CGFloat(envelope[lo..<hi].max() ?? 0)
                let h = max(0.5, peak * (mid - 4))
                wave.move(to: CGPoint(x: CGFloat(column), y: mid - h))
                wave.addLine(to: CGPoint(x: CGFloat(column), y: mid + h))
            }
            context.stroke(wave, with: .color(.accentColor), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
