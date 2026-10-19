import SwiftUI

/// Helpers for turning a continuous beat position into bar/beat numbers.
struct BeatInfo {
    let position: Double
    let beatsPerBar: Int

    var beatIndex: Int { Int(position.rounded(.down)) }
    var beatInBar: Int { ((beatIndex % beatsPerBar) + beatsPerBar) % beatsPerBar }
    var bar: Int { Int((position / Double(beatsPerBar)).rounded(.down)) + 1 }
    var isCountIn: Bool { position < 0 }
    /// 1 on the beat, decaying to 0 within ~a third of a beat.
    var flash: Double { max(0, 1 - (position - position.rounded(.down)) * 3) }
}

/// The visual metronome strip above the grid.
struct BeatBar: View {
    @EnvironmentObject private var project: Project
    @EnvironmentObject private var transport: Transport

    var body: some View {
        TimelineView(.animation) { _ in
            let bpb = project.settings.beatsPerBar
            let info = transport.beatPosition(atHostTime: HostTime.now).map { BeatInfo(position: $0, beatsPerBar: bpb) }
            HStack(spacing: 22) {
                Text(label(info))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(info?.isCountIn == true ? .orange : .primary)
                    .frame(width: 210, alignment: .leading)

                HStack(spacing: 14) {
                    ForEach(0..<bpb, id: \.self) { beat in
                        BeatDot(beat: beat, info: info)
                    }
                }

                Spacer()

                Text("♩ = \(Int(project.settings.bpm.rounded()))   \(bpb)/4")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
        }
    }

    private func label(_ info: BeatInfo?) -> String {
        guard let info else {
            return transport.state == .calibrating ? "Calibrating…" : "Ready"
        }
        if info.isCountIn {
            return "Count-in  \(info.beatInBar + 1)"
        }
        return "Bar \(info.bar)  ·  Beat \(info.beatInBar + 1)"
    }
}

private struct BeatDot: View {
    let beat: Int
    let info: BeatInfo?

    var body: some View {
        let active = info?.beatInBar == beat
        let flash = active ? (info?.flash ?? 0) : 0
        let color: Color = info?.isCountIn == true ? .orange : (beat == 0 ? .red : .accentColor)
        Circle()
            .fill(active ? color : Color.secondary.opacity(0.25))
            .frame(width: beat == 0 ? 26 : 20, height: beat == 0 ? 26 : 20)
            .scaleEffect(1 + 0.35 * flash)
            .shadow(color: color.opacity(flash * 0.8), radius: 10 * flash)
            .frame(width: 34, height: 34)
    }
}
