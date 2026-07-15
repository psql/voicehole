import AppKit

// Renders 10 cartoon "tubular fish lips" icon variants on the vortex background
// and composites them into a labeled contact sheet.
// Usage: swift lipvariants.swift <sheet-out.png> [variant-out-dir]

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: lipvariants.swift <sheet-out.png> [variant-out-dir]\n", stderr)
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

// MARK: - Cartoon tubular lips

struct LipStyle {
    var name: String
    var width: CGFloat = 380
    var upperTube: CGFloat = 74
    var lowerTube: CGFloat = 90
    var bow: CGFloat = 46
    var lowerDepth: CGFloat = 55
    var lipColor = NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.55, alpha: 1)
    var lowerColor: NSColor? = nil          // defaults to lipColor darkened
    var outline = NSColor(calibratedRed: 0.24, green: 0.01, blue: 0.12, alpha: 1)
    var outlineW: CGFloat = 16
    var openO = false
    var oRadius: CGFloat = 145
    var oTube: CGFloat = 95
    var puckerLines = 0
    var rotation: CGFloat = 0
    var gloss = true
}

func upperLipPath(_ s: LipStyle) -> NSBezierPath {
    let c = center
    let h = s.width / 2
    let path = NSBezierPath()
    let L = CGPoint(x: c.x - h, y: c.y)
    let R = CGPoint(x: c.x + h, y: c.y)
    path.move(to: L)
    path.curve(to: CGPoint(x: c.x - s.width * 0.20, y: c.y + s.bow),
               controlPoint1: CGPoint(x: c.x - h * 0.72, y: c.y + s.bow * 0.45),
               controlPoint2: CGPoint(x: c.x - s.width * 0.32, y: c.y + s.bow))
    path.curve(to: CGPoint(x: c.x, y: c.y + s.bow * 0.60),
               controlPoint1: CGPoint(x: c.x - s.width * 0.10, y: c.y + s.bow),
               controlPoint2: CGPoint(x: c.x - s.width * 0.05, y: c.y + s.bow * 0.60))
    path.curve(to: CGPoint(x: c.x + s.width * 0.20, y: c.y + s.bow),
               controlPoint1: CGPoint(x: c.x + s.width * 0.05, y: c.y + s.bow * 0.60),
               controlPoint2: CGPoint(x: c.x + s.width * 0.10, y: c.y + s.bow))
    path.curve(to: R,
               controlPoint1: CGPoint(x: c.x + s.width * 0.32, y: c.y + s.bow),
               controlPoint2: CGPoint(x: c.x + h * 0.72, y: c.y + s.bow * 0.45))
    return path
}

func lowerLipPath(_ s: LipStyle) -> NSBezierPath {
    let c = center
    let h = s.width / 2
    let path = NSBezierPath()
    let L = CGPoint(x: c.x - h, y: c.y)
    let R = CGPoint(x: c.x + h, y: c.y)
    let bottom = CGPoint(x: c.x, y: c.y - s.lowerDepth)
    path.move(to: L)
    path.curve(to: bottom,
               controlPoint1: CGPoint(x: c.x - h * 0.60, y: c.y - s.lowerDepth),
               controlPoint2: CGPoint(x: c.x - h * 0.25, y: c.y - s.lowerDepth))
    path.curve(to: R,
               controlPoint1: CGPoint(x: c.x + h * 0.25, y: c.y - s.lowerDepth),
               controlPoint2: CGPoint(x: c.x + h * 0.60, y: c.y - s.lowerDepth))
    return path
}

func strokeTube(_ path: NSBezierPath, width: CGFloat, color: NSColor, outline: NSColor, outlineW: CGFloat) {
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width + outlineW * 2
    outline.setStroke()
    path.stroke()
    path.lineWidth = width
    color.setStroke()
    path.stroke()
}

func drawLips(_ s: LipStyle) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    if s.rotation != 0 {
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: s.rotation * .pi / 180)
        ctx.translateBy(x: -center.x, y: -center.y)
    }

    let lowerColor = s.lowerColor ?? lerpColor(s.lipColor, .black, 0.18)

    if s.openO {
        // puckered "O" ring — blowing a kiss into the void
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - s.oRadius, y: center.y - s.oRadius,
            width: s.oRadius * 2, height: s.oRadius * 2
        ))
        ring.lineWidth = s.oTube + s.outlineW * 2
        s.outline.setStroke()
        ring.stroke()
        ring.lineWidth = s.oTube
        s.lipColor.setStroke()
        ring.stroke()
        // black mouth hole
        let hole = NSBezierPath(ovalIn: NSRect(
            x: center.x - (s.oRadius - s.oTube / 2) - s.outlineW,
            y: center.y - (s.oRadius - s.oTube / 2) - s.outlineW,
            width: (s.oRadius - s.oTube / 2 + s.outlineW) * 2,
            height: (s.oRadius - s.oTube / 2 + s.outlineW) * 2
        ))
        NSColor.black.setFill()
        hole.fill()
        // pucker creases radiating out
        for i in 0..<s.puckerLines {
            let angle = CGFloat(i) / CGFloat(s.puckerLines) * 2 * .pi + .pi / CGFloat(s.puckerLines)
            let r0 = s.oRadius + s.oTube / 2 + s.outlineW + 8
            let r1 = r0 + 34
            let line = NSBezierPath()
            line.move(to: CGPoint(x: center.x + r0 * cos(angle), y: center.y + r0 * sin(angle)))
            line.line(to: CGPoint(x: center.x + r1 * cos(angle), y: center.y + r1 * sin(angle)))
            line.lineWidth = 12
            line.lineCapStyle = .round
            s.outline.withAlphaComponent(0.85).setStroke()
            line.stroke()
        }
        if s.gloss {
            let g = NSBezierPath(ovalIn: NSRect(x: center.x - s.oRadius * 0.55, y: center.y + s.oRadius * 0.62, width: 74, height: 34))
            NSColor.white.withAlphaComponent(0.4).setFill()
            g.fill()
        }
    } else {
        let upper = upperLipPath(s)
        let lower = lowerLipPath(s)
        // lower first so the upper tube overlaps the seam
        strokeTube(lower, width: s.lowerTube, color: lowerColor, outline: s.outline, outlineW: s.outlineW)
        strokeTube(upper, width: s.upperTube, color: s.lipColor, outline: s.outline, outlineW: s.outlineW)
        // re-stroke seam so the meeting line reads
        let seam = NSBezierPath()
        seam.move(to: CGPoint(x: center.x - s.width / 2, y: center.y))
        seam.curve(to: CGPoint(x: center.x + s.width / 2, y: center.y),
                   controlPoint1: CGPoint(x: center.x - s.width * 0.22, y: center.y - 14),
                   controlPoint2: CGPoint(x: center.x + s.width * 0.22, y: center.y - 14))
        seam.lineWidth = s.outlineW * 0.9
        seam.lineCapStyle = .round
        s.outline.setStroke()
        seam.stroke()

        if s.puckerLines > 0 {
            let spread = s.width * 0.16
            for i in 0..<s.puckerLines {
                let t = CGFloat(i) / CGFloat(max(s.puckerLines - 1, 1)) - 0.5
                let x = center.x + t * spread * 2
                let line = NSBezierPath()
                line.move(to: CGPoint(x: x, y: center.y + s.bow * 0.30))
                line.line(to: CGPoint(x: x, y: center.y - 24))
                line.lineWidth = 9
                line.lineCapStyle = .round
                s.outline.withAlphaComponent(0.55).setStroke()
                line.stroke()
            }
        }
        if s.gloss {
            let g = NSBezierPath(ovalIn: NSRect(
                x: center.x - s.width * 0.17,
                y: center.y - s.lowerDepth - s.lowerTube * 0.28,
                width: s.width * 0.34, height: s.lowerTube * 0.30
            ))
            NSColor.white.withAlphaComponent(0.30).setFill()
            g.fill()
        }
    }
    ctx.restoreGState()
}

// MARK: - Variants

let hotPink = NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.55, alpha: 1)
let bubblegum = NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.72, alpha: 1)
let coral = NSColor(calibratedRed: 1.0, green: 0.44, blue: 0.40, alpha: 1)
let cartoonRed = NSColor(calibratedRed: 0.92, green: 0.14, blue: 0.20, alpha: 1)
let neonMagenta = NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.80, alpha: 1)

var variants: [LipStyle] = [
    LipStyle(name: "1 · Classic Pucker"),
    LipStyle(name: "2 · Big Duckface", width: 430, upperTube: 96, lowerTube: 116, bow: 52, lowerDepth: 62, lipColor: hotPink),
    LipStyle(name: "3 · Kissy O", lipColor: hotPink, openO: true, oRadius: 140, oTube: 96, puckerLines: 10),
    LipStyle(name: "4 · Wide Fish", width: 480, upperTube: 72, lowerTube: 84, bow: 30, lowerDepth: 44, lipColor: coral),
    LipStyle(name: "5 · Thicc Red", width: 400, upperTube: 102, lowerTube: 126, bow: 50, lowerDepth: 64, lipColor: cartoonRed),
    LipStyle(name: "6 · Smirk", width: 390, upperTube: 84, lowerTube: 102, bow: 48, lowerDepth: 56, lipColor: hotPink, rotation: 9),
    LipStyle(name: "7 · Neon Hole", width: 400, upperTube: 88, lowerTube: 106, bow: 48, lowerDepth: 58,
             lipColor: NSColor(calibratedRed: 0.22, green: 0.02, blue: 0.16, alpha: 1),
             lowerColor: NSColor(calibratedRed: 0.16, green: 0.01, blue: 0.12, alpha: 1),
             outline: neonMagenta, outlineW: 14, gloss: false),
    LipStyle(name: "8 · Bubblegum", width: 410, upperTube: 92, lowerTube: 112, bow: 50, lowerDepth: 60, lipColor: bubblegum,
             outline: NSColor(calibratedRed: 0.30, green: 0.05, blue: 0.35, alpha: 1)),
    LipStyle(name: "9 · Pout Lines", width: 395, upperTube: 86, lowerTube: 104, bow: 48, lowerDepth: 58, lipColor: hotPink, puckerLines: 5),
    LipStyle(name: "10 · Mega Mouth", width: 500, upperTube: 112, lowerTube: 140, bow: 60, lowerDepth: 72, lipColor: cartoonRed, outlineW: 18),
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

// contact sheet: 5 x 2 grid
let cell: CGFloat = 470
let labelH: CGFloat = 64
let cols = 5, rows = 2
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
        savePNG(rep, args[2] + "/variant-\(i + 1).png")
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
