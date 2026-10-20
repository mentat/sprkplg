// Draws SparkPlug's app icon (a yellow bolt on an ink square) at every size macOS asks for and
// writes them into App/Assets.xcassets/AppIcon.appiconset. Run: `swift scripts/make-icon.swift`.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // The macOS icon grid: an 824-point rounded square centred on a 1024 canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    color(0x16151c).setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: color(0x2a2836), ending: color(0x121117))!.draw(in: shape, angle: -90)

    // The bolt from the logo (24×24, y down), scaled into the tile.
    let pts: [(CGFloat, CGFloat)] = [(13, 3), (13, 10), (19, 10), (11, 21), (11, 14), (5, 14)]
    let unit = 824 * s / 24 * 0.78
    let ox = tile.midX - 12 * unit, oy = tile.midY + 12 * unit
    let bolt = NSBezierPath()
    for (i, p) in pts.enumerated() {
        let pt = NSPoint(x: ox + p.0 * unit, y: oy - p.1 * unit)
        if i == 0 { bolt.move(to: pt) } else { bolt.line(to: pt) }
    }
    bolt.close()
    bolt.lineJoinStyle = .round
    bolt.lineWidth = 1.4 * unit
    color(0xffd84d).setFill()
    color(0xffd84d).setStroke()
    bolt.fill()
    bolt.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try draw(points * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(out.path)")
