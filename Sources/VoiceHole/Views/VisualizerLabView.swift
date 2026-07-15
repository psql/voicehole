import SwiftUI

/// Playground for dialing in the recording-orb aesthetic. Live preview on top
/// (simulated audio or the real mic while recording), sliders below.
/// "Copy Values" puts the current numbers on the clipboard to send back for
/// committing as defaults.
struct VisualizerLabView: View {
    @EnvironmentObject private var recorder: RecorderService
    @ObservedObject private var settings = OrbSettings.shared
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(.black)
                OrbVisualizer()
                if !recorder.isRecording && !settings.simulate {
                    Text("Enable “Simulate Audio” below, or start a recording")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(minHeight: 260)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    slider("count", $settings.count, step: 1)
                    slider("ripple", $settings.ripple)
                    slider("scale", $settings.scale)
                    slider("speed", $settings.speed)
                    slider("gain", $settings.gain)
                    slider("floor", $settings.floor)
                    slider("stiffness", $settings.stiffness)
                    slider("damping", $settings.damping)
                    slider("size", $settings.size)
                    slider("variation", $settings.variation)
                    slider("blur", $settings.blur)
                    slider("fill", $settings.fill)
                    slider("glow", $settings.glow)
                }
                .padding()
            }

            Divider()

            HStack {
                Toggle("Simulate Audio", isOn: $settings.simulate)
                    .toggleStyle(.switch)
                Spacer()
                Button("Reset") { settings.reset() }
                Button {
                    Clipboard.copy(settings.snapshot)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied!" : "Copy Values", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 680)
        #endif
        .onAppear {
            if !recorder.isRecording { settings.simulate = true }
        }
    }

    private func slider(_ name: String, _ value: Binding<Double>, step: Double? = nil) -> some View {
        let param = OrbSettings.params[name]!
        return HStack(spacing: 10) {
            Text(param.label)
                .frame(width: 130, alignment: .trailing)
                .font(.callout)
            if let step {
                Slider(value: value, in: param.range, step: step)
            } else {
                Slider(value: value, in: param.range)
            }
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
