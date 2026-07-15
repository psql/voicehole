import AppKit

// 10 variations of the VoiceHole icon: purple + yellow spiral arms with
// twinkling stars around the retro Big Laugh mouth.
// Usage: swift iconstarvariants.swift <sheet-out.png> [variant-out-dir]

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: iconstarvariants.swift <sheet-out.png> [variant-out-dir]\n", stderr)
    exit(1)
}

let size: CGFloat = 1024
let center = CGPoint(x: size / 2, y: size / 2)

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

func lerpColor(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    let a = a.usingColorSpace(.deviceRGB)!
    let b = b.usingColorSpace(.deviceRGB)!
    return NSColor(
        calibratedRed: lerp(a.redComponent, b.redComponent, t),
        green: lerp(a.greenComponent, b.greenComponent, t),
        blue: lerp(a.blueComponent, b.blueComponent, t),
        alpha: lerp(a.alphaComponent, b.alphaComponent, t)
    )
}

// Deterministic per-variant randomness so renders are reproducible.
struct Rand {
    var seed: UInt64
    mutating func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((seed >> 33) % 100_000) / 100_000
    }
    mutating func range(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo + next() * (hi - lo) }
}

// MARK: - Palette

let purple = NSColor(calibratedRed: 0.58, green: 0.32, blue: 0.97, alpha: 1)
let deepPurple = NSColor(calibratedRed: 0.34, green: 0.14, blue: 0.68, alpha: 1)
let lavender = NSColor(calibratedRed: 0.72, green: 0.55, blue: 1.0, alpha: 1)
let yellow = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.25, alpha: 1)
let gold = NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.10, alpha: 1)
let cream = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.78, alpha: 1)
let white = NSColor.white

// MARK: - Style

struct StarConfig {
    var count = 26
    var colors: [NSColor] = [yellow, cream]
    var minSize: CGFloat = 9
    var maxSize: CGFloat = 30
    var dots = 14              // extra tiny round stars
}

struct IconStyle {
    var name: String
    var bgInner = NSColor(calibratedRed: 0.20, green: 0.07, blue: 0.38, alpha: 1)
    var bgOuter = NSColor(calibratedRed: 0.03, green: 0.01, blue: 0.09, alpha: 1)
    // per-arm gradient stops (outer → inner), cycled across the 3 arms
    var armOuter: [NSColor] = [deepPurple]
    var armInner: [NSColor] = [purple]
    var stars = StarConfig()
    var seed: UInt64 = 1
}

// MARK: - Drawing

func spiralPoint(theta: CGFloat, phase: CGFloat, rMax: CGFloat, rMin: CGFloat, thetaMax: CGFloat) -> CGPoint {
    let k = log(rMax / rMin) / thetaMax
    let r = rMax * exp(-k * theta)
    let angle = theta + phase
    return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
}

func drawSpiralArm(phase: CGFloat, outer: NSColor, inner: NSColor) {
    let thetaMax: CGFloat = 1.25 * 2 * .pi
    let steps = 340
    let outerClear = outer.usingColorSpace(.deviceRGB)!.withAlphaComponent(0)

    for i in 0..<steps {
        let t0 = CGFloat(i) / CGFloat(steps)
        let t1 = CGFloat(i + 1) / CGFloat(steps)
        let p0 = spiralPoint(theta: t0 * thetaMax, phase: phase, rMax: 700, rMin: 170, thetaMax: thetaMax)
        let p1 = spiralPoint(theta: t1 * thetaMax, phase: phase, rMax: 700, rMin: 170, thetaMax: thetaMax)

        let seg = NSBezierPath()
        seg.move(to: p0)
        seg.line(to: p1)
        seg.lineCapStyle = .round

        seg.lineWidth = lerp(120, 30, t0)
        lerpColor(outerClear, inner, t0).withAlphaComponent(lerp(0.05, 0.3, t0)).setStroke()
        seg.stroke()

        seg.lineWidth = lerp(58, 12, t0)
        lerpColor(outer, inner, t0).withAlphaComponent(lerp(0.35, 1.0, t0)).setStroke()
        seg.stroke()
    }
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

    // soft glow, then the sparkle itself
    color.withAlphaComponent(0.22).setFill()
    starPath(s * 1.7).fill()
    color.setFill()
    starPath(s).fill()
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(ovalIn: NSRect(x: -s * 0.10, y: -s * 0.10, width: s * 0.2, height: s * 0.2)).fill()

    ctx.restoreGState()
}

func drawStars(_ config: StarConfig, seed: UInt64, bgPath: NSBezierPath) {
    var rng = Rand(seed: seed)
    var placed = 0
    var attempts = 0
    while placed < config.count && attempts < config.count * 30 {
        attempts += 1
        let p = CGPoint(x: rng.range(120, size - 120), y: rng.range(120, size - 120))
        let d = hypot(p.x - center.x, p.y - center.y)
        if d < 300 { continue }                       // keep the mouth clear
        guard bgPath.contains(p) else { continue }
        let s = rng.range(config.minSize, config.maxSize)
        let color = config.colors[Int(rng.next() * 100) % config.colors.count]
        let rot = rng.next() < 0.45 ? CGFloat.pi / 4 : 0
        drawSparkle(at: p, size: s, color: color.withAlphaComponent(rng.range(0.65, 1.0)), rotation: rot)
        placed += 1
    }
    // tiny round stars
    for _ in 0..<config.dots {
        let p = CGPoint(x: rng.range(120, size - 120), y: rng.range(120, size - 120))
        let d = hypot(p.x - center.x, p.y - center.y)
        if d < 290 || !bgPath.contains(p) { continue }
        let r = rng.range(2.5, 6)
        let color = config.colors[Int(rng.next() * 100) % config.colors.count]
        color.withAlphaComponent(rng.range(0.5, 0.95)).setFill()
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
    hole.draw(fromCenter: center, radius: 0, toCenter: center, radius: 265, options: [])
}

// Retro "Big Laugh" mouth (same as genicon.swift)
func drawMouth() {
    let c = center
    let rx: CGFloat = 205, ry: CGFloat = 205, lip: CGFloat = 74, line: CGFloat = 24, teethH: CGFloat = 92
    let lipColor = NSColor(calibratedRed: 0.91, green: 0.30, blue: 0.12, alpha: 1)
    let tongueColor = NSColor(calibratedRed: 0.85, green: 0.18, blue: 0.14, alpha: 1)

    let outerRect = NSRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)
    let innerRect = outerRect.insetBy(dx: lip, dy: lip)
    let outer = NSBezierPath(ovalIn: outerRect)
    let inner = NSBezierPath(ovalIn: innerRect)
    let innerRx = rx - lip, innerRy = ry - lip

    let ring = NSBezierPath()
    ring.append(outer)
    ring.append(inner)
    ring.windingRule = .evenOdd
    lipColor.setFill()
    ring.fill()

    NSColor.black.setFill()
    inner.fill()

    NSGraphicsContext.current!.saveGraphicsState()
    inner.addClip()

    let bandBottom = c.y + innerRy - teethH
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(x: innerRect.minX, y: bandBottom, width: innerRect.width, height: teethH + 4)).fill()
    NSColor.black.setStroke()
    let edge = NSBezierPath()
    edge.move(to: CGPoint(x: innerRect.minX, y: bandBottom))
    edge.line(to: CGPoint(x: innerRect.maxX, y: bandBottom))
    edge.lineWidth = line * 0.85
    edge.stroke()
    for i in 1..<4 {
        let x = innerRect.minX + innerRect.width * CGFloat(i) / 4
        let sep = NSBezierPath()
        sep.move(to: CGPoint(x: x, y: bandBottom))
        sep.line(to: CGPoint(x: x, y: c.y + innerRy))
        sep.lineWidth = line * 0.7
        sep.stroke()
    }

    let tw = innerRx * 1.5, th = innerRy * 1.1
    let tongue = NSBezierPath(ovalIn: NSRect(x: c.x - tw / 2, y: c.y - innerRy - th * 0.42, width: tw, height: th))
    tongueColor.setFill()
    tongue.fill()
    tongue.lineWidth = line * 0.85
    NSColor.black.setStroke()
    tongue.stroke()

    NSGraphicsContext.current!.restoreGraphicsState()

    NSColor.black.setStroke()
    inner.lineWidth = line
    inner.stroke()
    outer.lineWidth = line
    outer.stroke()
}

func render(_ style: IconStyle) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 92, dy: 92), xRadius: 190, yRadius: 190)
    bgPath.addClip()

    let bg = NSGradient(colors: [style.bgInner, style.bgOuter])!
    bg.draw(fromCenter: center, radius: 40, toCenter: center, radius: 660, options: [])

    for arm in 0..<3 {
        drawSpiralArm(
            phase: CGFloat(arm) * 2 * .pi / 3,
            outer: style.armOuter[arm % style.armOuter.count],
            inner: style.armInner[arm % style.armInner.count]
        )
    }
    drawStars(style.stars, seed: style.seed, bgPath: bgPath)
    drawBlackHole()
    drawMouth()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Variants

let variants: [IconStyle] = [
    IconStyle(name: "1 · Purple + Gold Stars",
              armOuter: [deepPurple], armInner: [purple],
              stars: StarConfig(count: 22, colors: [yellow, gold], minSize: 10, maxSize: 26, dots: 12), seed: 11),
    IconStyle(name: "2 · Purple→Yellow Arms",
              armOuter: [deepPurple], armInner: [yellow],
              stars: StarConfig(count: 20, colors: [cream, yellow], minSize: 9, maxSize: 24, dots: 12), seed: 22),
    IconStyle(name: "3 · Alternating Arms",
              armOuter: [deepPurple, gold, deepPurple], armInner: [purple, yellow, purple],
              stars: StarConfig(count: 18, colors: [cream, white], minSize: 8, maxSize: 22, dots: 10), seed: 33),
    IconStyle(name: "4 · Golden Vortex",
              armOuter: [NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.05, alpha: 1)], armInner: [yellow],
              stars: StarConfig(count: 24, colors: [purple, lavender, white], minSize: 9, maxSize: 26, dots: 14), seed: 44),
    IconStyle(name: "5 · Starfield Dense",
              armOuter: [deepPurple], armInner: [purple],
              stars: StarConfig(count: 42, colors: [yellow, cream, white], minSize: 7, maxSize: 22, dots: 30), seed: 55),
    IconStyle(name: "6 · Big Twinkles",
              armOuter: [deepPurple], armInner: [lavender],
              stars: StarConfig(count: 12, colors: [yellow, gold], minSize: 20, maxSize: 42, dots: 8), seed: 66),
    IconStyle(name: "7 · Lavender + Gold",
              armOuter: [purple], armInner: [lavender],
              stars: StarConfig(count: 24, colors: [gold, cream], minSize: 10, maxSize: 26, dots: 14), seed: 77),
    IconStyle(name: "8 · Yellow Core",
              bgOuter: NSColor(calibratedRed: 0.05, green: 0.02, blue: 0.12, alpha: 1),
              armOuter: [purple], armInner: [gold],
              stars: StarConfig(count: 26, colors: [yellow, white], minSize: 8, maxSize: 24, dots: 16), seed: 88),
    IconStyle(name: "9 · Royal Night",
              bgInner: NSColor(calibratedRed: 0.26, green: 0.10, blue: 0.48, alpha: 1),
              armOuter: [deepPurple], armInner: [purple],
              stars: StarConfig(count: 30, colors: [yellow, gold, cream], minSize: 9, maxSize: 28, dots: 20), seed: 99),
    IconStyle(name: "10 · Cosmic Max",
              armOuter: [deepPurple, NSColor(calibratedRed: 0.45, green: 0.28, blue: 0.05, alpha: 1), deepPurple],
              armInner: [purple, yellow, lavender],
              stars: StarConfig(count: 36, colors: [yellow, gold, cream, white], minSize: 8, maxSize: 30, dots: 24), seed: 110),
]

// MARK: - Contact sheet

func savePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let cell: CGFloat = 470
let labelH: CGFloat = 64
let cols = 5, rows = 2
let sheetW = CGFloat(cols) * cell
let sheetH = CGFloat(rows) * (cell + labelH)
let sheet = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(sheetW), pixelsHigh: Int(sheetH),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: sheetW, height: sheetH)).fill()

let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 28),
    .foregroundColor: NSColor.white,
]

for (i, style) in variants.enumerated() {
    let rep = render(style)
    if args.count >= 3 {
        savePNG(rep, args[2] + "/star-\(i + 1).png")
    }
    let col = i % cols
    let row = i / cols
    let x = CGFloat(col) * cell
    let y = sheetH - CGFloat(row + 1) * (cell + labelH) + labelH
    let img = NSImage(size: NSSize(width: size, height: size))
    img.addRepresentation(rep)
    img.draw(in: NSRect(x: x + 5, y: y, width: cell - 10, height: cell - 10))
    let label = NSAttributedString(string: style.name, attributes: labelAttrs)
    let lsize = label.size()
    label.draw(at: NSPoint(x: x + (cell - lsize.width) / 2, y: y - labelH + 14))
}
NSGraphicsContext.restoreGraphicsState()
savePNG(sheet, args[1])
print("done")
