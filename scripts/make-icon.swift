// Draws the app icon and writes Resources/AppIcon.icns and docs/images/icon.png.
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024

/// A section of a ring with rounded corners. Angles in degrees, clockwise from the top.
func wedge(center: CGPoint, mid: CGFloat, span: CGFloat, inner: CGFloat, outer: CGFloat, gap: CGFloat, corner: CGFloat) -> CGPath {
    func edges(_ r: CGFloat) -> (CGFloat, CGFloat) {
        let inset = gap / 2 / r * 180 / .pi
        return (mid - span / 2 + inset, mid + span / 2 - inset)
    }
    // y points up in this context, so clockwise-from-top becomes 90° minus the angle.
    func point(_ r: CGFloat, _ deg: CGFloat) -> CGPoint {
        let a = (90 - deg) * .pi / 180
        return CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
    }
    func rad(_ deg: CGFloat) -> CGFloat { (90 - deg) * .pi / 180 }
    let (os, oe) = edges(outer), (istart, ie) = edges(inner)
    let od = corner / outer * 180 / .pi, id = corner / inner * 180 / .pi
    let path = CGMutablePath()
    path.move(to: point(outer - corner, edges(outer - corner).0))
    path.addQuadCurve(to: point(outer, os + od), control: point(outer, os))
    path.addArc(center: center, radius: outer, startAngle: rad(os + od), endAngle: rad(oe - od), clockwise: true)
    path.addQuadCurve(to: point(outer - corner, edges(outer - corner).1), control: point(outer, oe))
    path.addLine(to: point(inner + corner, edges(inner + corner).1))
    path.addQuadCurve(to: point(inner, ie - id), control: point(inner, ie))
    path.addArc(center: center, radius: inner, startAngle: rad(ie - id), endAngle: rad(istart + id), clockwise: false)
    path.addQuadCurve(to: point(inner + corner, edges(inner + corner).0), control: point(inner, istart))
    path.closeSubpath()
    return path
}

func gradient(_ colors: [NSColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil)!
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    // The plate: Apple's icon grid leaves a 100 px margin for the shadow.
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(platePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient([NSColor(red: 0.20, green: 0.23, blue: 0.31, alpha: 1), NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // A soft glow behind the highlighted wedge.
    ctx.drawRadialGradient(gradient([NSColor(red: 0.25, green: 0.55, blue: 1, alpha: 0.35), NSColor(red: 0.25, green: 0.55, blue: 1, alpha: 0)]),
                           startCenter: CGPoint(x: 700, y: 640), startRadius: 0, endCenter: CGPoint(x: 700, y: 640), endRadius: 420, options: [])
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    for i in 0..<6 {
        let highlighted = i == 1
        let path = wedge(center: center, mid: CGFloat(i) * 60, span: 60, inner: 158, outer: highlighted ? 336 : 310, gap: 24, corner: 22)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if highlighted {
            ctx.drawLinearGradient(gradient([NSColor(red: 0.42, green: 0.72, blue: 1, alpha: 1), NSColor(red: 0.04, green: 0.42, blue: 1, alpha: 1)]),
                                   start: CGPoint(x: 600, y: 860), end: CGPoint(x: 760, y: 480), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        } else {
            ctx.drawLinearGradient(gradient([NSColor(white: 1, alpha: 0.30), NSColor(white: 1, alpha: 0.10)]),
                                   start: CGPoint(x: 512, y: 840), end: CGPoint(x: 512, y: 184), options: [])
        }
        ctx.restoreGState()
        // The rim of the glass.
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(white: 1, alpha: highlighted ? 0.55 : 0.28).cgColor)
        ctx.setLineWidth(4)
        ctx.strokePath()
    }
    // The hub.
    let hub = CGRect(x: 512 - 104, y: 512 - 104, width: 208, height: 208)
    ctx.setFillColor(NSColor(white: 1, alpha: 0.16).cgColor)
    ctx.fillEllipse(in: hub)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.32).cgColor)
    ctx.setLineWidth(4)
    ctx.strokeEllipse(in: hub)

    // The plate's top edge catches the light.
    ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.12).cgColor)
    ctx.setLineWidth(4)
    ctx.strokePath()
    return true
}

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let tool = Process()
tool.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
tool.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try tool.run()
tool.waitUntilExit()
try fm.createDirectory(atPath: "docs/images", withIntermediateDirectories: true)
try png(512).write(to: URL(fileURLWithPath: "docs/images/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/images/icon.png")
