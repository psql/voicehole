import AppKit

// Retro 30s/40s cartoon open-mouth variants: even lip ring, black interior,
// blob tongue, optional teeth band — flat colors, uniform black monoline.
// Usage: swift lipretro.swift <sheet-out.png> [variant-out-dir]

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: lipretro.swift <sheet-out.png> [variant-out-dir]\n", stderr)
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

// MARK: - Retro cartoon mouth

struct RetroStyle {
    var name: String
    var rx: CGFloat = 200        // outer mouth half-width
    var ry: CGFloat = 180        // outer mouth half-height
    var lip: CGFloat = 56        // lip ring thickness
    var line: CGFloat = 24       // black monoline weight
    var lipColor = NSColor(calibratedRed: 0.91, green: 0.30, blue: 0.12, alpha: 1)
    var teeth = false
    var teethH: CGFloat = 80
    var tongue = true
    var tongueColor = NSColor(calibratedRed: 0.96, green: 0.42, blue: 0.60, alpha: 1)
    var tongueScale: CGFloat = 1.0
}

func drawMouth(_ s: RetroStyle) {
    let c = center
    let outerRect = NSRect(x: c.x - s.rx, y: c.y - s.ry, width: s.rx * 2, height: s.ry * 2)
    let innerRect = outerRect.insetBy(dx: s.lip, dy: s.lip)
    let outer = NSBezierPath(ovalIn: outerRect)
    let inner = NSBezierPath(ovalIn: innerRect)
    let innerRx = s.rx - s.lip
    let innerRy = s.ry - s.lip

    // lip ring
    let ring = NSBezierPath()
    ring.append(outer)
    ring.append(inner)
    ring.windingRule = .evenOdd
    s.lipColor.setFill()
    ring.fill()

    // mouth interior — the void
    NSColor.black.setFill()
    inner.fill()

    NSGraphicsContext.current!.saveGraphicsState()
    inner.addClip()

    // teeth band across the top
    if s.teeth {
        let bandBottom = c.y + innerRy - s.teethH
        let band = NSRect(x: innerRect.minX, y: bandBottom, width: innerRect.width, height: s.teethH + 4)
        NSColor.white.setFill()
        NSBezierPath(rect: band).fill()

        NSColor.black.setStroke()
        // bottom edge of the teeth
        let edge = NSBezierPath()
        edge.move(to: CGPoint(x: innerRect.minX, y: bandBottom))
        edge.line(to: CGPoint(x: innerRect.maxX, y: bandBottom))
        edge.lineWidth = s.line * 0.85
        edge.stroke()
        // separators
        let count = 4
        for i in 1..<count {
            let x = innerRect.minX + innerRect.width * CGFloat(i) / CGFloat(count)
            let sep = NSBezierPath()
            sep.move(to: CGPoint(x: x, y: bandBottom))
            sep.line(to: CGPoint(x: x, y: c.y + innerRy))
            sep.lineWidth = s.line * 0.7
            sep.stroke()
        }
    }

    // blob tongue rising from the bottom
    if s.tongue {
        let tw = innerRx * 1.5 * s.tongueScale
        let th = innerRy * 1.1 * s.tongueScale
        let tongueRect = NSRect(x: c.x - tw / 2, y: c.y - innerRy - th * 0.42, width: tw, height: th)
        let tongue = NSBezierPath(ovalIn: tongueRect)
        s.tongueColor.setFill()
        tongue.fill()
        tongue.lineWidth = s.line * 0.85
        NSColor.black.setStroke()
        tongue.stroke()
    }

    NSGraphicsContext.current!.restoreGraphicsState()

    // monoline outlines
    NSColor.black.setStroke()
    inner.lineWidth = s.line
    inner.stroke()
    outer.lineWidth = s.line
    outer.stroke()
}

// MARK: - Variants

let orange = NSColor(calibratedRed: 0.91, green: 0.30, blue: 0.12, alpha: 1)
let pinkLip = NSColor(calibratedRed: 0.95, green: 0.44, blue: 0.62, alpha: 1)
let tonguePink = NSColor(calibratedRed: 0.96, green: 0.42, blue: 0.60, alpha: 1)
let tongueRed = NSColor(calibratedRed: 0.85, green: 0.18, blue: 0.14, alpha: 1)

let variants: [RetroStyle] = [
    RetroStyle(name: "1 · Round + Tongue"),
    RetroStyle(name: "2 · Teeth + Tongue", teeth: true, tongueScale: 0.9),
    RetroStyle(name: "3 · Wide Bean", rx: 240, ry: 150, lip: 52, tongueScale: 1.1),
    RetroStyle(name: "4 · Big Laugh", rx: 205, ry: 205, lip: 54, teeth: true, teethH: 92, tongueColor: tongueRed),
    RetroStyle(name: "5 · Pink Ring", lipColor: pinkLip, tongueColor: tongueRed),
    RetroStyle(name: "6 · Tall Holler", rx: 175, ry: 215, lip: 52, tongueScale: 0.95),
]

// MARK: - Rendering

func makeBitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
}

func renderVariant(_ style: RetroStyle) -> NSBitmapImageRep {
    let rep = makeBitmap(Int(size), Int(size))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 92, dy: 92), xRadius: 190, yRadius: 190)
    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    bgPath.addClip()
    drawBackground()
    drawMouth(style)
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
        savePNG(rep, args[2] + "/retro-\(i + 1).png")
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
