import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject private var project: Project
    @EnvironmentObject private var transport: Transport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Latency Calibration").font(.title2.bold())
            Text("Sound takes time to leave your Mac, reach your ears, and come back in through the mic as your voice. Without correction every new layer lands a little late, and the error stacks up track after track. Measure it once for each audio setup.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        Text("**Speakers:** unplug headphones, turn the volume up and stay quiet. The mic hears the 10 clicks directly.")
                    } icon: { Image(systemName: "hifispeaker") }
                    Label {
                        Text("**Headphones:** clap sharply on each of the 10 clicks. This also measures your own sense of the beat, which is what you'll sing against.")
                    } icon: { Image(systemName: "hands.clap") }
                    Label {
                        Text("Avoid Bluetooth headphones while recording. They add 150–300 ms of delay that changes from moment to moment.")
                    } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(6)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await transport.calibrate() }
                } label: {
                    Text(transport.state == .calibrating ? "Listening…" : "Run Calibration")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .disabled(transport.state != .idle || transport.cameraStatus != .ready)
                if transport.state == .calibrating {
                    ProgressView().controlSize(.small)
                }
                if let result = transport.lastCalibration {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Measured \(ms(result.latency)) ms from \(result.hits) of \(result.total) clicks")
                        Text("Spread ±\(ms(result.spread)) ms" + (result.spread > 0.015 ? ". That's inconsistent, so try again." : ". Consistent."))
                            .foregroundStyle(result.spread > 0.015 ? .orange : .secondary)
                    }
                    .font(.callout)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Compensation for new takes:")
                    Text("\(ms(transport.latencyCompensation)) ms").monospacedDigit().bold()
                    if !transport.isCalibrated {
                        Text("(estimated from the output device)").foregroundStyle(.secondary)
                    }
                }
                Slider(value: Binding(
                    get: { transport.latencyCompensation * 1000 },
                    set: { project.settings.calibratedLatency = ($0 / 1000).rounded(toPlaces: 3) }
                ), in: 0...400, step: 1) {
                    Text("Manual")
                }
                HStack {
                    Text("Each take keeps the compensation it was recorded with. To fine-tune existing takes, use Align.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use Estimate") { project.settings.calibratedLatency = nil }
                        .disabled(!transport.isCalibrated)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(transport.state == .calibrating)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func ms(_ seconds: Double) -> Int { Int((seconds * 1000).rounded()) }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
