import AppKit

// Renders monoline 1940s-cartoon-style lip variants on the vortex background.
// Usage: swift lipmonoline.swift <sheet-out.png> [variant-out-dir]

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: lipmonoline.swift <sheet-out.png> [variant-out-dir]\n", stderr)
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

// MARK: - Monoline lips

struct LipStyle {
    var name: String
    var width: CGFloat = 400
    var bump: CGFloat = 95       // upper lip bump height
    var depth: CGFloat = 110     // lower lip depth
    var line: CGFloat = 26       // the one line weight
    var fill: NSColor? = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.55, alpha: 1)
    var stroke = NSColor.black
    var openO = false
    var oOuter: CGFloat = 165
    var oInner: CGFloat = 82
    var heart = false            // exaggerated cupid's bow
}

func lipsPath(_ s: LipStyle) -> NSBezierPath {
    let c = center
    let h = s.width / 2
    let bump = s.bump
    let peakX = s.width * (s.heart ? 0.24 : 0.21)
    let peakY = s.heart ? bump * 1.12 : bump
    let dipY = s.heart ? bump * 0.38 : bump * 0.55

    let path = NSBezierPath()
    let L = CGPoint(x: c.x - h, y: c.y)
    let R = CGPoint(x: c.x + h, y: c.y)
    path.move(to: L)
    path.curve(to: CGPoint(x: c.x - peakX, y: c.y + peakY),
               controlPoint1: CGPoint(x: c.x - h * 0.86, y: c.y + peakY * 0.72),
               controlPoint2: CGPoint(x: c.x - s.width * 0.33, y: c.y + peakY))
    path.curve(to: CGPoint(x: c.x, y: c.y + dipY),
               controlPoint1: CGPoint(x: c.x - s.width * 0.10, y: c.y + peakY),
               controlPoint2: CGPoint(x: c.x - s.width * 0.05, y: c.y + dipY))
    path.curve(to: CGPoint(x: c.x + peakX, y: c.y + peakY),
               controlPoint1: CGPoint(x: c.x + s.width * 0.05, y: c.y + dipY),
               controlPoint2: CGPoint(x: c.x + s.width * 0.10, y: c.y + peakY))
    path.curve(to: R,
               controlPoint1: CGPoint(x: c.x + s.width * 0.33, y: c.y + peakY),
               controlPoint2: CGPoint(x: c.x + h * 0.86, y: c.y + peakY * 0.72))
    path.curve(to: CGPoint(x: c.x, y: c.y - s.depth),
               controlPoint1: CGPoint(x: c.x + h * 0.94, y: c.y - s.depth * 0.85),
               controlPoint2: CGPoint(x: c.x + h * 0.42, y: c.y - s.depth))
    path.curve(to: L,
               controlPoint1: CGPoint(x: c.x - h * 0.42, y: c.y - s.depth),
               controlPoint2: CGPoint(x: c.x - h * 0.94, y: c.y - s.depth * 0.85))
    path.close()
    return path
}

func drawLips(_ s: LipStyle) {
    if s.openO {
        let outer = NSBezierPath(ovalIn: NSRect(
            x: center.x - s.oOuter, y: center.y - s.oOuter, width: s.oOuter * 2, height: s.oOuter * 2))
        let inner = NSBezierPath(ovalIn: NSRect(
            x: center.x - s.oInner, y: center.y - s.oInner, width: s.oInner * 2, height: s.oInner * 2))
        if let fill = s.fill {
            let ring = NSBezierPath()
            ring.append(outer)
            ring.append(inner)
            ring.windingRule = .evenOdd
            fill.setFill()
            ring.fill()
        }
        NSColor.black.setFill()
        inner.fill()
        s.stroke.setStroke()
        outer.lineWidth = s.line
        outer.stroke()
        inner.lineWidth = s.line
        inner.stroke()
        return
    }

    let path = lipsPath(s)
    if let fill = s.fill {
        fill.setFill()
        path.fill()
    }
    path.lineWidth = s.line
    path.lineJoinStyle = .round
    s.stroke.setStroke()
    path.stroke()

    // seam — same line weight, monoline
    let seam = NSBezierPath()
    seam.move(to: CGPoint(x: center.x - s.width / 2, y: center.y))
    seam.curve(to: CGPoint(x: center.x + s.width / 2, y: center.y),
               controlPoint1: CGPoint(x: center.x - s.width * 0.22, y: center.y - 16),
               controlPoint2: CGPoint(x: center.x + s.width * 0.22, y: center.y - 16))
    seam.lineWidth = s.line
    seam.lineCapStyle = .round
    s.stroke.setStroke()
    seam.stroke()
}

// MARK: - Variants

let pink = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.55, alpha: 1)
let red = NSColor(calibratedRed: 0.93, green: 0.16, blue: 0.22, alpha: 1)
let ivory = NSColor(calibratedRed: 0.97, green: 0.94, blue: 0.86, alpha: 1)
let ink = NSColor(calibratedRed: 0.07, green: 0.02, blue: 0.08, alpha: 1)

let variants: [LipStyle] = [
    LipStyle(name: "1 · Pink Classic", fill: pink, stroke: ink),
    LipStyle(name: "2 · Cartoon Red", fill: red, stroke: ink),
    LipStyle(name: "3 · Retro Ivory", fill: ivory, stroke: ink),
    LipStyle(name: "4 · Outline Only", fill: nil, stroke: pink),
    LipStyle(name: "5 · Kiss Ring", fill: pink, stroke: ink, openO: true),
    LipStyle(name: "6 · Wide Grin", width: 470, bump: 72, depth: 84, fill: pink, stroke: ink),
    LipStyle(name: "7 · Tall Pout", width: 330, bump: 115, depth: 135, fill: red, stroke: ink),
    LipStyle(name: "8 · Heart Bow", width: 390, bump: 100, depth: 112, fill: pink, stroke: ink, heart: true),
]

// MARK: - Rendering

func makeBitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
}

func renderVariant(_ style: LipStyle) -> NSBitmapImageRep {
    let rep = makeBitmap(Int(size), Int(size))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 92, dy: 92), xRadius: 190, yRadius: 190)
    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    bgPath.addClip()
    drawBackground()
    drawLips(style)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let cell: CGFloat = 470
let labelH: CGFloat = 64
let cols = 4, rows = 2
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
        savePNG(rep, args[2] + "/mono-\(i + 1).png")
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
