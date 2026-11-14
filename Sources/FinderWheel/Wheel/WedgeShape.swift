import SwiftUI

/// A section of a ring. Angles are in degrees, clockwise from the top.
/// `gap` is the constant-width space left to the neighbouring wedge, in points.
/// Corners are rounded by `cornerRadius`, shrunk to fit narrow or thin wedges.
struct WedgeShape: Shape {
    var centerDegrees: Double
    var spanDegrees: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    var gap: CGFloat = 4
    var cornerRadius: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // SwiftUI measures angles from the positive x axis; with y pointing down,
        // increasing angles run clockwise on screen. "Up" is therefore -90°.
        func edges(at radius: CGFloat) -> (start: Double, end: Double) {
            let inset = Double(gap / 2 / radius) * 180 / .pi
            return (centerDegrees - spanDegrees / 2 + inset - 90, centerDegrees + spanDegrees / 2 - inset - 90)
        }
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            let r = degrees * .pi / 180
            return CGPoint(x: center.x + CGFloat(cos(r)) * radius, y: center.y + CGFloat(sin(r)) * radius)
        }
        let outer = edges(at: outerRadius)
        let inner = edges(at: innerRadius)
        let innerArcLength = CGFloat((inner.end - inner.start) * .pi / 180) * innerRadius
        let corner = max(0, min(cornerRadius, (outerRadius - innerRadius) / 2, innerArcLength / 2))
        // Angular size of the corner along each arc.
        let outerDelta = Double(corner / outerRadius) * 180 / .pi
        let innerDelta = Double(corner / innerRadius) * 180 / .pi

        var path = Path()
        path.move(to: point(outerRadius - corner, outer.start))
        path.addQuadCurve(to: point(outerRadius, outer.start + outerDelta), control: point(outerRadius, outer.start))
        path.addArc(center: center, radius: outerRadius, startAngle: .degrees(outer.start + outerDelta),
                    endAngle: .degrees(outer.end - outerDelta), clockwise: false)
        path.addQuadCurve(to: point(outerRadius - corner, outer.end), control: point(outerRadius, outer.end))
        path.addLine(to: point(innerRadius + corner, inner.end))
        path.addQuadCurve(to: point(innerRadius, inner.end - innerDelta), control: point(innerRadius, inner.end))
        path.addArc(center: center, radius: innerRadius, startAngle: .degrees(inner.end - innerDelta),
                    endAngle: .degrees(inner.start + innerDelta), clockwise: true)
        path.addQuadCurve(to: point(innerRadius + corner, inner.start), control: point(innerRadius, inner.start))
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
