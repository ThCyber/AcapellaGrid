// Renders the Acapella Grid app icon.
// Usage: swift Tools/make_icon.swift <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Flip to a top-left origin.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, alpha])!
}

func linearGradient(_ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

// macOS icon grid: 824×824 body centred on a 1024 canvas, leaving room for the shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x1B1442))
ctx.fillPath()
ctx.restoreGState()

// Background: deep night-indigo stage.
linearGradient(bodyPath, [color(0x2A1E66), color(0x120C2E)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))

// Four voices: four tiles, each a different colour.
let gap: CGFloat = 26
let inset: CGFloat = 92
let tileSize = (body.width - inset * 2 - gap) / 2
let tileColors: [(UInt32, UInt32)] = [
    (0xFF7A6B, 0xF2416B), // soprano – coral
    (0xFFC75A, 0xFF8F3D), // alto – amber
    (0x4FE0C4, 0x1FA8B8), // tenor – teal
    (0x7CB8FF, 0x5B6CFF), // bass – blue
]
// Waveform bar heights per tile (fractions of tile height) – different melodies, same beat.
let waves: [[CGFloat]] = [
    [0.22, 0.48, 0.70, 0.40, 0.58],
    [0.36, 0.62, 0.30, 0.66, 0.26],
    [0.52, 0.30, 0.60, 0.44, 0.70],
    [0.28, 0.66, 0.46, 0.24, 0.54],
]

var tileRects: [CGRect] = []
for i in 0..<4 {
    let x = body.minX + inset + CGFloat(i % 2) * (tileSize + gap)
    let y = body.minY + inset + CGFloat(i / 2) * (tileSize + gap)
    let rect = CGRect(x: x, y: y, width: tileSize, height: tileSize)
    tileRects.append(rect)
    let path = CGPath(roundedRect: rect, cornerWidth: 64, cornerHeight: 64, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(path)
    ctx.setFillColor(color(tileColors[i].1))
    ctx.fillPath()
    ctx.restoreGState()
    linearGradient(path, [color(tileColors[i].0), color(tileColors[i].1)],
                   from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))

    // Top sheen.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let sheen = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: nil)!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    ctx.restoreGState()
}

// Waveform bars: columns line up across tiles = the tracks are in sync.
let barCount = 5
let barWidth: CGFloat = 26
for (i, rect) in tileRects.enumerated() {
    let spacing = (rect.width - 2 * 46 - barWidth) / CGFloat(barCount - 1)
    for b in 0..<barCount {
        let h = waves[i][b] * rect.height
        let bx = rect.minX + 46 + CGFloat(b) * spacing
        let bar = CGRect(x: bx, y: rect.midY - h / 2, width: barWidth, height: h)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.setFillColor(color(0xFFFFFF, 0.92))
        ctx.fillPath()
    }
}

// Centre: the shared beat / record button where all four tiles meet.
let centre = CGPoint(x: body.midX, y: body.midY)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 30, color: color(0x000000, 0.45))
ctx.addEllipse(in: CGRect(x: centre.x - 92, y: centre.y - 92, width: 184, height: 184))
ctx.setFillColor(color(0x1A123D))
ctx.fillPath()
ctx.restoreGState()
// Beat pulse rings.
for (r, a) in [(84.0, 0.95), (70.0, 0.0)] {
    ctx.addEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
    ctx.setStrokeColor(color(0xFFFFFF, a))
    ctx.setLineWidth(10)
    ctx.strokePath()
}
let dot = CGRect(x: centre.x - 52, y: centre.y - 52, width: 104, height: 104)
linearGradient(CGPath(ellipseIn: dot, transform: nil), [color(0xFF5A5F), color(0xE0193A)],
               from: CGPoint(x: dot.minX, y: dot.minY), to: CGPoint(x: dot.maxX, y: dot.maxY))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
