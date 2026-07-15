import AppKit

// Monoline "kiss ring" variants: puckered O-mouth with real lip shape, optional tongue.
// Usage: swift lipkissring.swift <sheet-out.png> [variant-out-dir]

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: lipkissring.swift <sheet-out.png> [variant-out-dir]\n", stderr)
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

// MARK: - Vortex background (same as genicon)

func spiralPoint(theta: CGFloat, phase: CGFloat, rMax: CGFloat, rMin: CGFloat, thetaMax: CGFloat) -> CGPoint {
    let k = log(rMax / rMin) / thetaMax
    let r = rMax * exp(-k * theta)
    let angle = theta + phase
    return CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
}

func drawSpiralArm(phase: CGFloat) {
    let thetaMax: CGFloat = 1.25 * 2 * .pi
    let steps = 340
    let outerColor = NSColor(calibratedRed: 0.42, green: 0.24, blue: 0.85, alpha: 0.0)
    let innerColor = NSColor(calibratedRed: 1.0, green: 0.42, blue: 0.78, alpha: 0.95)

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
        lerpColor(outerColor, innerColor, t0).withAlphaComponent(lerp(0.05, 0.3, t0)).setStroke()
        seg.stroke()

        seg.lineWidth = lerp(58, 12, t0)
        lerpColor(outerColor, innerColor, t0).withAlphaComponent(lerp(0.35, 1.0, t0)).setStroke()
        seg.stroke()
    }
}

func drawBackground() {
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.17, green: 0.06, blue: 0.32, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.01, blue: 0.08, alpha: 1),
    ])!
    bg.draw(fromCenter: center, radius: 40, toCenter: center, radius: 660, options: [])

    for arm in 0..<3 {
        drawSpiralArm(phase: CGFloat(arm) * 2 * .pi / 3)
    }

    let hole = NSGradient(colorsAndLocations:
        (NSColor.black, 0.0),
        (NSColor.black, 0.55),
        (NSColor(calibratedRed: 0.08, green: 0.01, blue: 0.12, alpha: 0.85), 0.75),
        (NSColor.black.withAlphaComponent(0.0), 1.0)
    )!
    hole.draw(fromCenter: center, radius: 0, toCenter: center, radius: 265, options: [])
}

// MARK: - Puckered O lips

enum Tongue {
    case none
    case peek      // tip poking up inside the mouth hole
    case loll      // hanging out over the lower lip
}

struct KissStyle {
    var name: String
    var R: CGFloat = 195          // outer lip silhouette radius
    var hole: CGFloat = 85        // mouth opening radius
    var bowPeak: CGFloat = 0.98   // cupid's bow peak height (× R)
    var bowDip: CGFloat = 0.68    // cupid's bow dip height (× R)
    var line: CGFloat = 26
    var fill = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.55, alpha: 1)
    var stroke = NSColor(calibratedRed: 0.07, green: 0.02, blue: 0.08, alpha: 1)
    var tongueColor = NSColor(calibratedRed: 0.94, green: 0.24, blue: 0.35, alpha: 1)
    var tongue: Tongue = .none
}

func outerLipPath(_ s: KissStyle) -> NSBezierPath {
    let c = center
    let R = s.R
    let peak = CGPoint(x: 0.42 * R, y: s.bowPeak * R)
    let dipY = s.bowDip * R

    let path = NSBezierPath()
    let left = CGPoint(x: c.x - R, y: c.y)
    let right = CGPoint(x: c.x + R, y: c.y)
    path.move(to: left)
    // up the left side to the left bow peak
    path.curve(to: CGPoint(x: c.x - peak.x, y: c.y + peak.y),
               controlPoint1: CGPoint(x: c.x - R * 1.0, y: c.y + R * 0.55),
               controlPoint2: CGPoint(x: c.x - R * 0.74, y: c.y + peak.y))
    // into the cupid's bow dip
    path.curve(to: CGPoint(x: c.x, y: c.y + dipY),
               controlPoint1: CGPoint(x: c.x - R * 0.20, y: c.y + peak.y),
               controlPoint2: CGPoint(x: c.x - R * 0.10, y: c.y + dipY))
    // out of the dip to the right peak
    path.curve(to: CGPoint(x: c.x + peak.x, y: c.y + peak.y),
               controlPoint1: CGPoint(x: c.x + R * 0.10, y: c.y + dipY),
               controlPoint2: CGPoint(x: c.x + R * 0.20, y: c.y + peak.y))
    // down the right side
    path.curve(to: right,
               controlPoint1: CGPoint(x: c.x + R * 0.74, y: c.y + peak.y),
               controlPoint2: CGPoint(x: c.x + R * 1.0, y: c.y + R * 0.55))
    // full round bottom
    path.curve(to: CGPoint(x: c.x, y: c.y - R),
               controlPoint1: CGPoint(x: c.x + R * 1.0, y: c.y - R * 0.62),
               controlPoint2: CGPoint(x: c.x + R * 0.56, y: c.y - R))
    path.curve(to: left,
               controlPoint1: CGPoint(x: c.x - R * 0.56, y: c.y - R),
               controlPoint2: CGPoint(x: c.x - R * 1.0, y: c.y - R * 0.62))
    path.close()
    return path
}

func drawKiss(_ s: KissStyle) {
    let c = center
    let outer = outerLipPath(s)
    let holeRect = NSRect(x: c.x - s.hole, y: c.y - s.hole, width: s.hole * 2, height: s.hole * 2)
    let hole = NSBezierPath(ovalIn: holeRect)

    // flat lip fill with the mouth opening punched out
    let ring = NSBezierPath()
    ring.append(outer)
    ring.append(hole)
    ring.windingRule = .evenOdd
    s.fill.setFill()
    ring.fill()

    // black mouth
    NSColor.black.setFill()
    hole.fill()

    // tongue tip peeking inside the mouth (clipped to the hole)
    if s.tongue == .peek {
        NSGraphicsContext.current!.saveGraphicsState()
        hole.addClip()
        let tw = s.hole * 1.45
        let top = c.y - s.hole * 0.12
        let tongueRect = NSRect(x: c.x - tw / 2, y: top - tw * 1.4, width: tw, height: tw * 1.4)
        let tongue = NSBezierPath(roundedRect: tongueRect, xRadius: tw / 2, yRadius: tw / 2)
        s.tongueColor.setFill()
        tongue.fill()
        tongue.lineWidth = s.line * 0.8
        s.stroke.setStroke()
        tongue.stroke()
        let crease = NSBezierPath()
        crease.move(to: CGPoint(x: c.x, y: tongueRect.maxY - 14))
        crease.line(to: CGPoint(x: c.x, y: tongueRect.maxY - tw * 0.42))
        crease.lineWidth = s.line * 0.7
        crease.lineCapStyle = .round
        crease.stroke()
        NSGraphicsContext.current!.restoreGraphicsState()
    }

    // monoline outlines
    hole.lineWidth = s.line
    s.stroke.setStroke()
    hole.stroke()
    outer.lineWidth = s.line
    outer.lineJoinStyle = .round
    outer.stroke()

    // big cartoon tongue hanging out over the lower lip — drawn on top of everything
    if s.tongue == .loll {
        let tw = s.hole * 1.9
        let top = c.y + s.hole * 0.15
        let bottom = c.y - s.R - 42
        let tongueRect = NSRect(x: c.x - tw / 2, y: bottom, width: tw, height: top - bottom)
        let tongue = NSBezierPath(roundedRect: tongueRect, xRadius: tw / 2, yRadius: tw / 2)
        s.tongueColor.setFill()
        tongue.fill()
        tongue.lineWidth = s.line
        tongue.lineJoinStyle = .round
        s.stroke.setStroke()
        tongue.stroke()
        let crease = NSBezierPath()
        crease.move(to: CGPoint(x: c.x, y: c.y - s.R * 0.42))
        crease.line(to: CGPoint(x: c.x, y: bottom + tw * 0.30))
        crease.lineWidth = s.line * 0.8
        crease.lineCapStyle = .round
        crease.stroke()
    }
}

// MARK: - Variants

let pink = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.55, alpha: 1)
let red = NSColor(calibratedRed: 0.93, green: 0.16, blue: 0.22, alpha: 1)
let tonguePink = NSColor(calibratedRed: 0.98, green: 0.42, blue: 0.52, alpha: 1)

let variants: [KissStyle] = [
    KissStyle(name: "1 · Lippy O", tongue: .none),
    KissStyle(name: "2 · Peek Tongue", tongue: .peek),
    KissStyle(name: "3 · Lolling Tongue", tongue: .loll),
    KissStyle(name: "4 · Big Hole + Peek", R: 205, hole: 105, tongue: .peek),
    KissStyle(name: "5 · Red + Loll", fill: red, tongueColor: tonguePink, tongue: .loll),
    KissStyle(name: "6 · Soft Bow + Peek", R: 200, hole: 88, bowPeak: 0.90, bowDip: 0.74, tongue: .peek),
]

// MARK: - Rendering

func makeBitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
}

func renderVariant(_ style: KissStyle) -> NSBitmapImageRep {
    let rep = makeBitmap(Int(size), Int(size))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 92, dy: 92), xRadius: 190, yRadius: 190)
    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    bgPath.addClip()
    drawBackground()
    drawKiss(style)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let cell: CGFloat = 470
let labelH: CGFloat = 64
let cols = 3, rows = 2
let sheetW = CGFloat(cols) * cell
let sheetH = CGFloat(rows) * (cell + labelH)
let sheet = makeBitmap(Int(sheetW), Int(sheetH))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: sheetW, height: sheetH)).fill()

let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 30),
    .foregroundColor: NSColor.white,
]

for (i, style) in variants.enumerated() {
    let rep = renderVariant(style)
    if args.count >= 3 {
        savePNG(rep, args[2] + "/kiss-\(i + 1).png")
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
