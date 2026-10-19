import SwiftUI

/// The 2×2 stage: one player layer renders every take; SwiftUI cells sit on top of it
/// in exactly the same layout as the composition.
struct GridStage: View {
    @EnvironmentObject private var transport: Transport

    var body: some View {
        ZStack {
            PlayerLayerView(player: transport.player)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    GridCell(index: 0)
                    GridCell(index: 1)
                }
                HStack(spacing: 0) {
                    GridCell(index: 2)
                    GridCell(index: 3)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GridCell: View {
    let index: Int
    @EnvironmentObject private var project: Project
    @EnvironmentObject private var transport: Transport
    @State private var hovering = false
    @State private var confirmDelete = false

    var body: some View {
        let track = project.tracks[index]
        ZStack {
            if transport.state.activeCell == index {
                CameraPreviewView(session: transport.recorder.session, mirrored: project.settings.mirrorVideo)
                RecordingOverlay(index: index)
            } else if let track {
                filledOverlay(track)
            } else {
                emptyCell
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { transport.cellTapped(index) }
        .onHover { hovering = $0 }
        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .confirmationDialog("Delete Track \(index + 1)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { project.replaceTrack(at: index, with: nil) }
        } message: {
            Text("The recorded video file will be removed.")
        }
    }

    private var emptyCell: some View {
        let canRecord = transport.state == .idle && transport.cameraStatus == .ready
        return ZStack {
            Color(white: hovering && canRecord ? 0.16 : 0.11)
            VStack(spacing: 10) {
                Image(systemName: "record.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(canRecord ? .red : .gray)
                Text("Track \(index + 1)")
                    .font(.title3.weight(.semibold))
                Text(emptyHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .opacity(canRecord || transport.state != .idle ? 1 : 0.6)
        }
    }

    private var emptyHint: String {
        switch transport.cameraStatus {
        case .denied: return "Camera/mic access denied"
        case .failed(let reason): return reason
        case .unknown: return "Starting camera…"
        case .ready: return transport.state == .idle ? "Click to record" : " "
        }
    }

    private func filledOverlay(_ track: TrackInfo) -> some View {
        ZStack {
            if transport.state == .playing {
                PlaybackPulse()
            }
            VStack {
                HStack {
                    Spacer()
                    if hovering && transport.state == .idle {
                        HStack(spacing: 6) {
                            cellButton("arrow.counterclockwise", help: "Re-record") {
                                Task { await transport.record(cell: index) }
                            }
                            cellButton(track.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                       help: track.muted ? "Unmute" : "Mute") {
                                project.tracks[index]?.muted.toggle()
                            }
                            cellButton("trash", help: "Delete") { confirmDelete = true }
                        }
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("Track \(index + 1)")
                    if track.muted { Image(systemName: "speaker.slash.fill") }
                    if track.nudge != 0 {
                        Text(String(format: "%+.0f ms", track.nudge * 1000)).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .shadow(radius: 3)
            }
            .padding(10)
        }
    }

    private func cellButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.55), in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Count-in numbers, REC badge and a border that flashes on every beat.
private struct RecordingOverlay: View {
    let index: Int
    @EnvironmentObject private var project: Project
    @EnvironmentObject private var transport: Transport

    var body: some View {
        TimelineView(.animation) { _ in
            let info = transport.beatPosition(atHostTime: HostTime.now)
                .map { BeatInfo(position: $0, beatsPerBar: project.settings.beatsPerBar) }
            let countIn = info?.isCountIn ?? true
            let accent: Color = countIn ? .orange : .red
            let flash = info?.flash ?? 0
            let downbeat = info?.beatInBar == 0

            ZStack {
                Rectangle()
                    .strokeBorder(accent.opacity(0.5 + 0.5 * flash), lineWidth: 3 + (downbeat ? 9 : 5) * flash)

                if let info, countIn {
                    VStack(spacing: 4) {
                        Text("\(info.beatInBar + 1)")
                            .font(.system(size: 96, weight: .heavy, design: .rounded))
                            .scaleEffect(1 + 0.25 * flash)
                        Text(info.bar == 0 ? "Get ready — pickups are recorded" : "Count-in")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                }

                VStack {
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 12, height: 12)
                            .opacity(countIn ? 0.4 : 0.6 + 0.4 * flash)
                        Text(countIn ? "ARMED" : "REC")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        if let info, !countIn {
                            Text("\(info.bar).\(info.beatInBar + 1)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    Spacer()
                    Text("Click here or press Space to stop")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.5), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(12)
            }
        }
    }
}

/// Subtle beat flash on filled cells during playback.
private struct PlaybackPulse: View {
    @EnvironmentObject private var project: Project
    @EnvironmentObject private var transport: Transport

    var body: some View {
        TimelineView(.animation) { _ in
            let info = transport.beatPosition(atHostTime: HostTime.now)
                .map { BeatInfo(position: $0, beatsPerBar: project.settings.beatsPerBar) }
            let flash = (info?.isCountIn ?? true) ? 0 : (info?.flash ?? 0)
            Rectangle()
                .strokeBorder(Color.accentColor.opacity(0.7 * flash),
                              lineWidth: info?.beatInBar == 0 ? 6 : 3)
        }
        .allowsHitTesting(false)
    }
}
