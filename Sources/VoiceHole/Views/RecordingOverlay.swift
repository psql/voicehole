import SwiftUI

/// Full-screen overlay while recording: unmistakable REC indicator, big timer,
/// and a scrolling bar visualizer that rides the input level.
struct RecordingOverlay: View {
    @EnvironmentObject private var recorder: RecorderService
    @ObservedObject private var recordingSettings = RecordingSettings.shared
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.62))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(.red)
                        .frame(width: 16, height: 16)
                        .opacity(pulsing ? 0.25 : 1)
                    Text("RECORDING")
                        .font(.title3.weight(.heavy))
                        .kerning(3)
                        .foregroundStyle(.red)
                }

                Text(Format.timestamp(recorder.elapsed))
                    .font(.system(size: 46, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                if let remaining = silenceCountdown {
                    Label("Silent — stopping in \(Format.timestamp(remaining))", systemImage: "moon.zzz.fill")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.yellow.opacity(0.9))
                        .transition(.opacity)
                }

                // flexible: takes whatever height is left, so small windows
                // shrink the bars instead of clipping the controls
                BarVisualizer(levels: recorder.levelHistory)
                    .frame(maxWidth: 520, maxHeight: .infinity)
                    .frame(minHeight: 80)
                    .padding(.vertical, 12)

                Label(sourceName, systemImage: sourceIcon)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                Button {
                    recorder.stop()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 64, height: 64)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.white)
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop recording")
                .keyboardShortcut("r", modifiers: .command)
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 16)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    /// Seconds until the silence auto-stop fires, shown once a pause has
    /// lasted long enough to be worth warning about.
    private var silenceCountdown: TimeInterval? {
        let timeout = recordingSettings.silenceTimeout
        guard timeout > 0, recorder.silenceDuration >= min(10, timeout / 2) else { return nil }
        return max(0, (timeout - recorder.silenceDuration).rounded(.up))
    }

    private var sourceName: String {
        if recorder.mode == .meeting { return "System Audio + Microphone" }
        return recorder.devices.first { $0.id == recorder.selectedDeviceID }?.name
            ?? "System Default Microphone"
    }

    private var sourceIcon: String {
        recorder.mode == .meeting ? "speaker.wave.2.fill" : "mic.fill"
    }
}

/// Rounded-tip bars, newest on the right, scrolling left as levels arrive.
/// Each bar is one level sample (0…1) mirrored around the center line.
struct BarVisualizer: View {
    let levels: [CGFloat]

    private let barWidth: CGFloat = 5
    private let gap: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let pitch = barWidth + gap
            let visible = Int(size.width / pitch)
            guard visible > 0 else { return }
            let shown = levels.suffix(visible)
            let midY = size.height / 2
            let maxHalf = (size.height - barWidth) / 2
            // Right-align so the newest sample always sits at the trailing edge.
            let originX = size.width - CGFloat(shown.count) * pitch + gap / 2

            for (i, level) in shown.enumerated() {
                let half = max(barWidth / 2, maxHalf * min(1, level))
                let rect = CGRect(
                    x: originX + CGFloat(i) * pitch,
                    y: midY - half,
                    width: barWidth,
                    height: half * 2
                )
                // Oldest bars fade out toward the left.
                let age = 1 - Double(i) / Double(max(1, shown.count - 1))
                let opacity = 0.25 + 0.75 * (1 - age * age)
                let color = level > 0.9 ? Color.red : Color.white
                context.fill(Capsule().path(in: rect), with: .color(color.opacity(opacity)))
            }
        }
    }
}
