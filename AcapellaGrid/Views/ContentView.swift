import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var project: Project
    @EnvironmentObject private var transport: Transport
    @State private var showAlign = false
    @State private var showCalibration = false

    var body: some View {
        VStack(spacing: 0) {
            ControlBar(showAlign: $showAlign, showCalibration: $showCalibration)
            Divider()
            BeatBar()
                .padding(.vertical, 12)
            GridStage()
                .padding(.horizontal, 20)
            StatusFooter()
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showAlign) {
            AlignmentView()
                .environmentObject(project)
                .environmentObject(transport)
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationView()
                .environmentObject(project)
                .environmentObject(transport)
        }
        .alert("Acapella Grid", isPresented: Binding(
            get: { transport.alertMessage != nil },
            set: { if !$0 { transport.alertMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(transport.alertMessage ?? "")
        }
        .onChange(of: project.tracks) { _, _ in
            Task { await transport.refreshPlayer() }
        }
        .onChange(of: [project.settings.bpm, Double(project.settings.beatsPerBar)]) { _, _ in
            Task { await transport.refreshPlayer() }
        }
        .onChange(of: project.settings.mirrorVideo) { _, _ in
            Task { await transport.refreshPlayer() }
        }
    }
}

private struct ControlBar: View {
    @EnvironmentObject private var project: Project
    @EnvironmentObject private var transport: Transport
    @Binding var showAlign: Bool
    @Binding var showCalibration: Bool
    @State private var showMetronome = false

    private var idle: Bool { transport.state == .idle }

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Text("Tempo").foregroundStyle(.secondary)
                TextField("BPM", value: $project.settings.bpm, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 54)
                    .multilineTextAlignment(.trailing)
                Stepper("BPM", value: $project.settings.bpm, in: 30...300, step: 1)
                    .labelsHidden()
                Text("BPM").foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .fixedSize()

            Picker("Meter", selection: $project.settings.beatsPerBar) {
                ForEach(2...7, id: \.self) { Text("\($0)/4").tag($0) }
            }
            .frame(width: 110)

            Stepper("Count-in: \(project.settings.countInBars) bar\(project.settings.countInBars == 1 ? "" : "s")",
                    value: $project.settings.countInBars, in: 1...4)
                .fixedSize()

            Button {
                showMetronome.toggle()
            } label: {
                Label("Click", systemImage: "metronome")
            }
            .popover(isPresented: $showMetronome, arrowEdge: .bottom) {
                MetronomeSettings().padding(16).frame(width: 260)
            }
            .disabled(false)

            Spacer()

            Button {
                transport.togglePlay()
            } label: {
                Label(playLabel, systemImage: playIcon)
                    .frame(minWidth: 70)
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .tint(transport.state.activeCell != nil ? .red : .accentColor)
            .disabled(transport.state == .idle && !project.hasTracks || transport.state == .calibrating)

            Button { showAlign = true } label: { Label("Align", systemImage: "waveform.path") }
                .disabled(!idle || !project.hasTracks)
            Button { showCalibration = true } label: { Label("Calibrate", systemImage: "dot.radiowaves.left.and.right") }
                .disabled(!idle)

            Menu {
                Button("Export Grid Video…") { exportVideo() }
                    .disabled(!project.hasTracks)
                Toggle("Mirror Video", isOn: $project.settings.mirrorVideo)
                Divider()
                Button("Show Project Folder") { NSWorkspace.shared.open(project.folder) }
                Button("Clear All Tracks", role: .destructive) { project.clearAll() }
                    .disabled(!project.hasTracks)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!idle)
        }
        .disabled(transport.state == .calibrating)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var playLabel: String {
        switch transport.state {
        case .playing, .countIn, .recording: "Stop"
        default: "Play"
        }
    }

    private var playIcon: String {
        switch transport.state {
        case .playing, .countIn, .recording: "stop.fill"
        default: "play.fill"
        }
    }

    private func exportVideo() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Acapella Grid.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await transport.export(to: url) }
    }
}

private struct MetronomeSettings: View {
    @EnvironmentObject private var project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Click while recording", isOn: $project.settings.clickDuringTake)
            Toggle("Click during playback", isOn: $project.settings.clickDuringPlayback)
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $project.settings.clickVolume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }
            Text("The count-in always clicks. The visual beat runs regardless of these settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatusFooter: View {
    @EnvironmentObject private var project: Project
    @EnvironmentObject private var transport: Transport

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "headphones")
            Text("Wear wired headphones while recording so earlier tracks and the click don't leak into the mic.")
            Spacer()
            if let progress = transport.exportProgress {
                ProgressView(value: progress).frame(width: 120)
                Text("Exporting…")
            } else {
                Text("Latency compensation: \(Int((transport.latencyCompensation * 1000).rounded())) ms")
                    .monospacedDigit()
                if !transport.isCalibrated {
                    Text("estimated — calibrate for best sync")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
