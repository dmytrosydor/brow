import AppKit

// make-icon.swift <out.iconset>: draws the brow mark (a raised brow over an
// eye) on a dark rounded square at every size an .icns needs.

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with a continuous-ish corner.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    let colors = [NSColor(red: 0.16, green: 0.13, blue: 0.17, alpha: 1).cgColor,
                  NSColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    // Mark, in a 100×100 box centred on the body (y grows up here).
    let box = body.width * 0.62
    let ox = s / 2 - box / 2, oy = s / 2 - box / 2
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x / 100 * box, y: oy + (100 - y) / 100 * box) }

    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1).cgColor)
    ctx.setLineWidth(box * 0.15)
    ctx.move(to: p(10, 40))
    ctx.addQuadCurve(to: p(92, 22), control: p(38, -4))
    ctx.strokePath()

    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(box * 0.065)
    let r = box * 0.15
    ctx.strokeEllipse(in: CGRect(x: p(50, 70).x - r, y: p(50, 70).y - r, width: 2 * r, height: 2 * r))
    ctx.setFillColor(NSColor.white.cgColor)
    let d = box * 0.055
    ctx.fillEllipse(in: CGRect(x: p(50, 70).x - d, y: p(50, 70).y - d, width: 2 * d, height: 2 * d))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
