import AppKit

/// Draws the menu bar icon: a ring of six dots when idle, a progress arc while jobs run,
/// and a dot in the corner when a job reported a failure.
enum StatusIcon {
    static func image(progress: Double?, warning: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.set()
            if let progress {
                let track = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
                track.lineWidth = 2
                NSColor.black.withAlphaComponent(0.3).setStroke()
                track.stroke()
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: 6, startAngle: 90,
                              endAngle: 90 - CGFloat(max(0.03, min(1, progress))) * 360, clockwise: true)
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            } else {
                for i in 0..<6 {
                    let angle = CGFloat(i) * .pi / 3
                    let dot = NSRect(x: center.x + sin(angle) * 5.5 - 1.6, y: center.y + cos(angle) * 5.5 - 1.6, width: 3.2, height: 3.2)
                    NSBezierPath(ovalIn: dot).fill()
                }
            }
            if warning {
                NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
