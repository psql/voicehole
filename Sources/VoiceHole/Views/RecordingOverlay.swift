import SwiftUI

/// Full-screen overlay while recording: unmistakable REC indicator, big timer,
/// and a loudness-breathing Perlin-rippled orb stack (davinciAudio orb style —
/// silence = gone, quiet = small and calm, loud = large and warbly).
struct RecordingOverlay: View {
    @EnvironmentObject private var recorder: RecorderService
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.62))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
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
                    .font(.system(size: 52, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                OrbVisualizer()
                    .frame(width: 380, height: 380)

                if let device = recorder.devices.first(where: { $0.id == recorder.selectedDeviceID }) {
                    Label(device.name, systemImage: "mic.fill")
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Label("System Default Microphone", systemImage: "mic.fill")
                        .foregroundStyle(.white.opacity(0.7))
                }

                Button {
                    recorder.stop()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 72, height: 72)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white)
                            .frame(width: 26, height: 26)
                    }
                }
                .buttonStyle(.plain)
                .help("Stop recording")
                .keyboardShortcut("r", modifiers: .command)
                .padding(.top, 6)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

/// Stacked Perlin-rippled orbs whose radius and warble ride the input level.
struct OrbVisualizer: View {
    @EnvironmentObject private var recorder: RecorderService

    private static let orbColors: [Color] = [
        Color(red: 0.62, green: 0.40, blue: 1.00),   // purple
        Color(red: 1.00, green: 0.35, blue: 0.65),   // hot pink
        Color(red: 1.00, green: 0.80, blue: 0.30),   // gold
        Color(red: 0.45, green: 0.55, blue: 1.00),   // violet blue
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // small floor so a dot breathes even in silence
                let amp = Double(max(0.07, recorder.displayLevel))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = Double(min(size.width, size.height)) * 0.46
                let ripple = 0.36 * min(amp * 1.3, 1)   // quiet = calm, loud = warbly

                context.blendMode = .screen
                for k in 0..<4 {
                    let dk = Double(k)
                    let seed = dk * 19.19
                    let radK = amp * maxRadius * (1 + 0.22 * sin(dk * 2.399))
                    let scaleK = 1.55 * (1 + 0.3 * sin(dk * 1.7 + 0.8))
                    let phase = t * (0.55 + 0.15 * dk) + seed

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

                    let color = Self.orbColors[k]
                    context.drawLayer { layer in
                        layer.blendMode = .screen
                        layer.addFilter(.blur(radius: 16))
                        layer.fill(path, with: .color(color.opacity(0.55)))
                    }
                    context.fill(path, with: .color(color.opacity(0.72)))
                }
            }
        }
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
