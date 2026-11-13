import SwiftUI

/// A section of a ring. Angles are in degrees, clockwise from the top.
/// `gap` is the constant-width space left to the neighbouring wedge, in points.
struct WedgeShape: Shape {
    var centerDegrees: Double
    var spanDegrees: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var gap: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // SwiftUI measures angles from the positive x axis; with y pointing down,
        // increasing angles run clockwise on screen. "Up" is therefore -90°.
        func edges(at radius: CGFloat) -> (start: Angle, end: Angle) {
            let inset = Double(gap / 2 / radius) * 180 / .pi
            return (.degrees(centerDegrees - spanDegrees / 2 + inset - 90),
                    .degrees(centerDegrees + spanDegrees / 2 - inset - 90))
        }
        let outer = edges(at: outerRadius)
        let inner = edges(at: innerRadius)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: outer.start, endAngle: outer.end, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: inner.end, endAngle: inner.start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

extension CGPoint {
    /// The point at `radius` from `center` in the direction `degrees` clockwise from the top (y down).
    static func polar(center: CGPoint, degrees: Double, radius: CGFloat) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: center.x + CGFloat(sin(r)) * radius, y: center.y - CGFloat(cos(r)) * radius)
    }
}
