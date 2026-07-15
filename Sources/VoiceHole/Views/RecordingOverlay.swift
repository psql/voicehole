import SwiftUI

/// Full-screen overlay while recording: unmistakable REC indicator, big timer,
/// and a loudness-breathing Perlin-rippled orb stack (davinciAudio orb style —
/// silence = gone, quiet = small and calm, loud = large and warbly).
struct RecordingOverlay: View {
    @EnvironmentObject private var recorder: RecorderService
    @State private var pulsing = false
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

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

                // flexible: takes whatever height is left, so small windows
                // shrink the orb instead of clipping the controls
                OrbVisualizer()
                    .frame(maxWidth: 460, maxHeight: .infinity)
                    .frame(minHeight: 120)

                Label(deviceName, systemImage: "mic.fill")
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
        #if os(macOS)
        .overlay(alignment: .topTrailing) {
            Button {
                openWindow(id: "visualizer-lab")
            } label: {
                Label("Tune", systemImage: "slider.horizontal.3")
                    .foregroundStyle(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .padding(14)
            .help("Open the Visualizer Lab")
        }
        #endif
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }

    private var deviceName: String {
        recorder.devices.first { $0.id == recorder.selectedDeviceID }?.name
            ?? "System Default Microphone"
    }
}

/// Stacked Perlin-rippled orbs whose radius and warble ride the input level.
/// All aesthetics come from OrbSettings (tunable in the Visualizer Lab).
struct OrbVisualizer: View {
    @EnvironmentObject private var recorder: RecorderService
    @ObservedObject private var settings = OrbSettings.shared

    private static let orbColors: [Color] = [
        Color(red: 0.62, green: 0.40, blue: 1.00),   // purple
        Color(red: 1.00, green: 0.35, blue: 0.65),   // hot pink
        Color(red: 1.00, green: 0.80, blue: 0.30),   // gold
        Color(red: 0.45, green: 0.55, blue: 1.00),   // violet blue
        Color(red: 0.30, green: 0.90, blue: 0.80),   // teal
        Color(red: 1.00, green: 0.55, blue: 0.25),   // orange
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let live: Double
                if recorder.isRecording {
                    live = Double(recorder.displayLevel)
                } else if settings.simulate {
                    live = Self.syntheticLevel(t)
                } else {
                    live = 0
                }
                // clamp so ripple peaks + variation + glow blur always fit the canvas
                let amp = min(max(settings.floor, live), 1.05)
                guard amp > 0.001 else { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let halfDim = Double(min(size.width, size.height)) / 2
                let headroom = (1 + settings.ripple) * (1 + settings.variation) * 1.05
                let maxRadius = max(10, halfDim - settings.blur - 4) / headroom * (settings.size / 0.5)
                let ripple = settings.ripple * min(amp * 1.3, 1)   // quiet = calm, loud = warbly
                let palette = Self.shuffledColors(seed: recorder.paletteSeed)

                context.blendMode = .screen
                let count = max(1, Int(settings.count.rounded()))
                for k in 0..<count {
                    let dk = Double(k)
                    let seed = dk * 19.19
                    let radK = amp * maxRadius * (1 + settings.variation * sin(dk * 2.399))
                    let scaleK = settings.scale * (1 + 0.3 * sin(dk * 1.7 + 0.8))
                    let phase = t * settings.speed * (1 + 0.15 * dk) + seed

                    var path = Path()
                    let segments = 150
                    for s in 0...segments {
                        let theta = Double(s) / Double(segments) * 2 * .pi
                        let noise = Perlin.noise(
                            cos(theta) * scaleK + seed * 0.37,
                            sin(theta) * scaleK - seed * 0.61,
                            phase
                        )
                        let radius = max(0, radK * (1 + ripple * noise))
                        let point = CGPoint(
                            x: center.x + CGFloat(cos(theta) * radius),
                            y: center.y + CGFloat(sin(theta) * radius)
                        )
                        if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.closeSubpath()

                    let color = palette[k % palette.count]
                    if settings.glow > 0.01, settings.blur > 0.1 {
                        context.drawLayer { layer in
                            layer.blendMode = .screen
                            layer.addFilter(.blur(radius: settings.blur))
                            layer.fill(path, with: .color(color.opacity(settings.glow)))
                        }
                    }
                    context.fill(path, with: .color(color.opacity(settings.fill)))
                }
            }
        }
    }

    /// Palette order derives from the recorder's per-recording seed, so every
    /// new recording gets its own color combination.
    static func shuffledColors(seed: UInt64) -> [Color] {
        var generator = SplitMix64(state: seed)
        return orbColors.shuffled(using: &generator)
    }

    /// Fake voice-ish envelope for tuning without recording.
    static func syntheticLevel(_ t: Double) -> Double {
        let phrase = max(0, sin(t * 0.9))                    // talking bursts
        let syllables = 0.5 + 0.5 * sin(t * 6.3 + sin(t * 2.1) * 2)
        let noise = 0.5 + 0.5 * Perlin.noise(t * 2.2, 0.7, 3.1)
        return min(1.2, phrase * (0.35 + 0.55 * syllables * noise))
    }
}

struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Classic Ken Perlin 3D noise (reference permutation), returns roughly -1…1.
enum Perlin {
    private static let permutation: [Int] = [
        151, 160, 137, 91, 90, 15, 131, 13, 201, 95, 96, 53, 194, 233, 7, 225,
        140, 36, 103, 30, 69, 142, 8, 99, 37, 240, 21, 10, 23, 190, 6, 148,
        247, 120, 234, 75, 0, 26, 197, 62, 94, 252, 219, 203, 117, 35, 11, 32,
        57, 177, 33, 88, 237, 149, 56, 87, 174, 20, 125, 136, 171, 168, 68, 175,
        74, 165, 71, 134, 139, 48, 27, 166, 77, 146, 158, 231, 83, 111, 229, 122,
        60, 211, 133, 230, 220, 105, 92, 41, 55, 46, 245, 40, 244, 102, 143, 54,
        65, 25, 63, 161, 1, 216, 80, 73, 209, 76, 132, 187, 208, 89, 18, 169,
        200, 196, 135, 130, 116, 188, 159, 86, 164, 100, 109, 198, 173, 186, 3, 64,
        52, 217, 226, 250, 124, 123, 5, 202, 38, 147, 118, 126, 255, 82, 85, 212,
        207, 206, 59, 227, 47, 16, 58, 17, 182, 189, 28, 42, 223, 183, 170, 213,
        119, 248, 152, 2, 44, 154, 163, 70, 221, 153, 101, 155, 167, 43, 172, 9,
        129, 22, 39, 253, 19, 98, 108, 110, 79, 113, 224, 232, 178, 185, 112, 104,
        218, 246, 97, 228, 251, 34, 242, 193, 238, 210, 144, 12, 191, 179, 162, 241,
        81, 51, 145, 235, 249, 14, 239, 107, 49, 192, 214, 31, 181, 199, 106, 157,
        184, 84, 204, 176, 115, 121, 50, 45, 127, 4, 150, 254, 138, 236, 205, 93,
        222, 114, 67, 29, 24, 72, 243, 141, 128, 195, 78, 66, 215, 61, 156, 180,
    ]
    private static let p: [Int] = permutation + permutation

    private static func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    private static func lerp(_ t: Double, _ a: Double, _ b: Double) -> Double { a + t * (b - a) }

    private static func grad(_ hash: Int, _ x: Double, _ y: Double, _ z: Double) -> Double {
        let h = hash & 15
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }

    static func noise(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let X = Int(floor(x)) & 255
        let Y = Int(floor(y)) & 255
        let Z = Int(floor(z)) & 255
        let xf = x - floor(x), yf = y - floor(y), zf = z - floor(z)
        let u = fade(xf), v = fade(yf), w = fade(zf)

        let a = p[X] + Y, aa = p[a] + Z, ab = p[a + 1] + Z
        let b = p[X + 1] + Y, ba = p[b] + Z, bb = p[b + 1] + Z

        return lerp(w,
            lerp(v,
                lerp(u, grad(p[aa], xf, yf, zf), grad(p[ba], xf - 1, yf, zf)),
                lerp(u, grad(p[ab], xf, yf - 1, zf), grad(p[bb], xf - 1, yf - 1, zf))),
            lerp(v,
                lerp(u, grad(p[aa + 1], xf, yf, zf - 1), grad(p[ba + 1], xf - 1, yf, zf - 1)),
                lerp(u, grad(p[ab + 1], xf, yf - 1, zf - 1), grad(p[bb + 1], xf - 1, yf - 1, zf - 1))))
    }
}
