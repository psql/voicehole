import AppKit

// Renders the VoiceHole app icon: a spiralling black-hole vortex with lips at the center.
// Usage: swift genicon.swift <mac-out.png> <ios-out.png>

let args = CommandLine.arguments
guard args.count == 3 else {
    fputs("usage: genicon.swift <mac-out.png> <ios-out.png>\n", stderr)
    exit(1)
}

let size: CGFloat = 1024
let center = CGPoint(x: size / 2, y: size / 2)

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

func lerpColor(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    NSColor(
        calibratedRed: lerp(a.redComponent, b.redComponent, t),
        green: lerp(a.greenComponent, b.greenComponent, t),
        blue: lerp(a.blueComponent, b.blueComponent, t),
        alpha: lerp(a.alphaComponent, b.alphaComponent, t)
    )
}

func spiralPoint(theta: CGFloat, phase: CGFloat, rMax: CGFloat, rMin: CGFloat, thetaMax: CGFloat) -> CGPoint {
    let k = log(rMax / rMin) / thetaMax
    let r = rMax * exp(-k * theta)
    let angle = theta + phase
    return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
}

func drawSpiralArm(phase: CGFloat) {
    let thetaMax: CGFloat = 1.25 * 2 * .pi
    let steps = 340
    // Golden Vortex: dark gold sweeping into bright yellow
    let outerColor = NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.05, alpha: 0.0)
    let innerColor = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.25, alpha: 0.95)

    for i in 0..<steps {
        let t0 = CGFloat(i) / CGFloat(steps)
        let t1 = CGFloat(i + 1) / CGFloat(steps)
        let p0 = spiralPoint(theta: t0 * thetaMax, phase: phase, rMax: 700, rMin: 170, thetaMax: thetaMax)
        let p1 = spiralPoint(theta: t1 * thetaMax, phase: phase, rMax: 700, rMin: 170, thetaMax: thetaMax)

        let seg = NSBezierPath()
        seg.move(to: p0)
        seg.line(to: p1)
        seg.lineCapStyle = .round

        // soft glow pass
        seg.lineWidth = lerp(120, 30, t0)
        lerpColor(outerColor, innerColor, t0).withAlphaComponent(lerp(0.05, 0.3, t0)).setStroke()
        seg.stroke()

        // bright core pass
        seg.lineWidth = lerp(58, 12, t0)
        lerpColor(outerColor, innerColor, t0).withAlphaComponent(lerp(0.35, 1.0, t0)).setStroke()
        seg.stroke()
    }
}

// Deterministic RNG so the icon renders identically every time.
struct Rand {
    var seed: UInt64
    mutating func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) % 100_000) / 100_000
    }
    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo + next() * (hi - lo) }
}

func drawSparkle(at p: CGPoint, size s: CGFloat, color: NSColor, rotation: CGFloat) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: rotation)

    func starPath(_ s: CGFloat) -> NSBezierPath {
        let c = s * 0.14
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 0, y: s))
        path.curve(to: CGPoint(x: s, y: 0), controlPoint1: CGPoint(x: c, y: c), controlPoint2: CGPoint(x: c, y: c))
        path.curve(to: CGPoint(x: 0, y: -s), controlPoint1: CGPoint(x: c, y: -c), controlPoint2: CGPoint(x: c, y: -c))
        path.curve(to: CGPoint(x: -s, y: 0), controlPoint1: CGPoint(x: -c, y: -c), controlPoint2: CGPoint(x: -c, y: -c))
        path.curve(to: CGPoint(x: 0, y: s), controlPoint1: CGPoint(x: -c, y: c), controlPoint2: CGPoint(x: -c, y: c))
        path.close()
        return path
    }

    color.withAlphaComponent(0.25).setFill()
    starPath(s * 1.7).fill()
    color.setFill()
    starPath(s).fill()
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: -s * 0.11, y: -s * 0.11, width: s * 0.22, height: s * 0.22)).fill()

    ctx.restoreGState()
}

// Big readable twinkles (few + large so they survive 16-32 px sizes).
func drawStars() {
    let colors = [
        NSColor(calibratedRed: 0.72, green: 0.55, blue: 1.0, alpha: 1),   // lavender
        NSColor(calibratedRed: 0.58, green: 0.32, blue: 0.97, alpha: 1),  // purple
        NSColor.white,
    ]
    var rng = Rand(seed: 44)
    var placed = 0
    var attempts = 0
    while placed < 9 && attempts < 300 {
        attempts += 1
        let p = CGPoint(x: rng.range(160, size - 160), y: rng.range(160, size - 160))
        if hypot(p.x - center.x, p.y - center.y) < 400 { continue }
        let s = rng.range(30, 56)
        let color = colors[Int(rng.next() * 100) % colors.count]
        let rot = rng.next() < 0.45 ? CGFloat.pi / 4 : 0
        drawSparkle(at: p, size: s, color: color.withAlphaComponent(rng.range(0.75, 1.0)), rotation: rot)
        placed += 1
    }
    for _ in 0..<7 {
        let p = CGPoint(x: rng.range(150, size - 150), y: rng.range(150, size - 150))
        if hypot(p.x - center.x, p.y - center.y) < 380 { continue }
        let r = rng.range(4, 8)
        colors[Int(rng.next() * 100) % colors.count].withAlphaComponent(rng.range(0.6, 0.95)).setFill()
        NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)).fill()
    }
}

func drawBlackHole() {
    let hole = NSGradient(colorsAndLocations:
        (NSColor.black, 0.0),
        (NSColor.black, 0.55),
        (NSColor(calibratedRed: 0.08, green: 0.01, blue: 0.12, alpha: 0.85), 0.75),
        (NSColor.black.withAlphaComponent(0.0), 1.0)
    )!
    hole.draw(fromCenter: center, radius: 0, toCenter: center, radius: 375, options: [])
}

// Retro 40s-cartoon "Big Laugh" mouth: thick even lip ring, black mouth-void,
// teeth band, red blob tongue — flat colors, uniform black monoline.
func drawLips() {
    let c = center
    let rx: CGFloat = 292
    let ry: CGFloat = 292
    let lip: CGFloat = 102
    let line: CGFloat = 30
    let teethH: CGFloat = 126

    let lipColor = NSColor(calibratedRed: 0.91, green: 0.30, blue: 0.12, alpha: 1)
    let tongueColor = NSColor(calibratedRed: 0.85, green: 0.18, blue: 0.14, alpha: 1)

    let outerRect = NSRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)
    let innerRect = outerRect.insetBy(dx: lip, dy: lip)
    let outer = NSBezierPath(ovalIn: outerRect)
    let inner = NSBezierPath(ovalIn: innerRect)
    let innerRx = rx - lip
    let innerRy = ry - lip

    // lip ring
    let ring = NSBezierPath()
    ring.append(outer)
    ring.append(inner)
    ring.windingRule = .evenOdd
    lipColor.setFill()
    ring.fill()

    // mouth interior — the void
    NSColor.black.setFill()
    inner.fill()

    NSGraphicsContext.current!.saveGraphicsState()
    inner.addClip()

    // teeth band across the top
    let bandBottom = c.y + innerRy - teethH
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: innerRect.minX, y: bandBottom, width: innerRect.width, height: teethH + 4)).fill()

    NSColor.black.setStroke()
    let edge = NSBezierPath()
    edge.move(to: CGPoint(x: innerRect.minX, y: bandBottom))
    edge.line(to: CGPoint(x: innerRect.maxX, y: bandBottom))
    edge.lineWidth = line * 0.85
    edge.stroke()
    let teethCount = 4
    for i in 1..<teethCount {
        let x = innerRect.minX + innerRect.width * CGFloat(i) / CGFloat(teethCount)
        let sep = NSBezierPath()
        sep.move(to: CGPoint(x: x, y: bandBottom))
        sep.line(to: CGPoint(x: x, y: c.y + innerRy))
        sep.lineWidth = line * 0.7
        sep.stroke()
    }

    // red blob tongue rising from the bottom
    let tw = innerRx * 1.5
    let th = innerRy * 1.1
    let tongue = NSBezierPath(ovalIn: NSRect(x: c.x - tw / 2, y: c.y - innerRy - th * 0.42, width: tw, height: th))
    tongueColor.setFill()
    tongue.fill()
    tongue.lineWidth = line * 0.85
    NSColor.black.setStroke()
    tongue.stroke()

    NSGraphicsContext.current!.restoreGraphicsState()

    // monoline outlines
    NSColor.black.setStroke()
    inner.lineWidth = line
    inner.stroke()
    outer.lineWidth = line
    outer.stroke()
}

func draw(fullBleed: Bool) {
    let full = NSRect(x: 0, y: 0, width: size, height: size)
    let bgPath: NSBezierPath
    if fullBleed {
        bgPath = NSBezierPath(rect: full)
    } else {
        bgPath = NSBezierPath(roundedRect: full.insetBy(dx: 92, dy: 92), xRadius: 190, yRadius: 190)
    }

    NSGraphicsContext.current!.saveGraphicsState()
    bgPath.addClip()

    // deep-space background
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.06, blue: 0.32, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.01, blue: 0.08, alpha: 1),
    ])!
    bg.draw(fromCenter: center, radius: 40, toCenter: center, radius: 660, options: [])

    for arm in 0..<3 {
        drawSpiralArm(phase: CGFloat(arm) * 2 * .pi / 3)
    }
    drawStars()
    drawBlackHole()
    drawLips()

    NSGraphicsContext.current!.restoreGraphicsState()
}

func render(fullBleed: Bool) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(fullBleed: fullBleed)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("failed to encode \(path)\n", stderr)
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: path))
}

save(render(fullBleed: false), to: args[1])
save(render(fullBleed: true), to: args[2])
print("done")
