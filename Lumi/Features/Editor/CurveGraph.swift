import SwiftUI

/// Point editing for a tone curve, kept apart from the view so it can be tested. Points are 0...1, y up (0 = black out, 1 = white out).
enum CurveEditing {
    static let maxPoints = 12
    static let minGap = 0.02

    /// Index of the point within `radius` of `p` (nearest first), or nil.
    static func nearest(_ pts: [CGPoint], to p: CGPoint, within radius: CGFloat) -> Int? {
        pts.indices.filter { hypot(pts[$0].x - p.x, pts[$0].y - p.y) <= radius }.min { hypot(pts[$0].x - p.x, pts[$0].y - p.y) < hypot(pts[$1].x - p.x, pts[$1].y - p.y) }
    }

    /// Moves a point. The end points keep their x; the others stay between their neighbours.
    static func move(_ pts: [CGPoint], index i: Int, to p: CGPoint) -> [CGPoint] {
        guard pts.indices.contains(i) else { return pts }
        var out = pts
        let y = min(max(p.y, 0), 1)
        if i == 0 || i == pts.count - 1 { out[i].y = y; return out }
        let lo = pts[i - 1].x + minGap, hi = pts[i + 1].x - minGap
        out[i] = CGPoint(x: min(max(p.x, lo), max(hi, lo)), y: y)
        return out
    }

    /// Adds a point on the curve at x, if there is room and no neighbour is closer than `minGap`. Returns the new list and the index.
    static func insert(_ pts: [CGPoint], at p: CGPoint) -> (points: [CGPoint], index: Int)? {
        guard pts.count < maxPoints, p.x > 0, p.x < 1, !pts.contains(where: { abs($0.x - p.x) < minGap }) else { return nil }
        var out = pts; out.append(CGPoint(x: p.x, y: min(max(p.y, 0), 1))); out.sort { $0.x < $1.x }
        return (out, out.firstIndex { $0.x == p.x } ?? 0)
    }

    /// Removes an inner point (the two ends stay).
    static func remove(_ pts: [CGPoint], index i: Int) -> [CGPoint] {
        guard pts.indices.contains(i), i != 0, i != pts.count - 1 else { return pts }
        var out = pts; out.remove(at: i); return out
    }
}

/// The curve as a graph: drag points, tap empty space to add one, double tap a point to remove it.
struct CurveGraph: View {
    @Binding var curve: ToneCurve
    var tint: Color = LumiColor.text
    var onEnd: () -> Void = {}
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { geo in
            content(geo.size)
        }
        .accessibilityElement().accessibilityLabel("Tone curve").accessibilityHint("Drag points to change it")
    }

    private func content(_ size: CGSize) -> some View {
        let w = size.width, h = size.height
        func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: (1 - p.y) * h) }
        func toCurve(_ p: CGPoint) -> CGPoint { CGPoint(x: min(max(p.x / w, 0), 1), y: min(max(1 - p.y / h, 0), 1)) }
        return Group {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LumiColor.well)
                Path { p in
                    for i in 1...3 { let f = CGFloat(i) / 4; p.move(to: CGPoint(x: w * f, y: 0)); p.addLine(to: CGPoint(x: w * f, y: h)); p.move(to: CGPoint(x: 0, y: h * f)); p.addLine(to: CGPoint(x: w, y: h * f)) }
                }.stroke(LumiColor.track, lineWidth: 1)
                Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: 0)) }.stroke(LumiColor.track, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Path { p in
                    for i in 0...64 { let x = Double(i) / 64; let pt = toView(CGPoint(x: x, y: curve.value(at: x))); i == 0 ? p.move(to: pt) : p.addLine(to: pt) }
                }.stroke(tint, lineWidth: 2.5)
                ForEach(Array(curve.points.enumerated()), id: \.offset) { i, pt in
                    Circle().fill(dragging == i ? LumiColor.accent : LumiColor.surface).overlay(Circle().stroke(tint, lineWidth: 2)).frame(width: 16, height: 16).position(toView(pt))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = toCurve(v.location)
                    if dragging == nil {
                        let start = toCurve(v.startLocation)
                        var pts = sortedPoints()
                        if let i = CurveEditing.nearest(pts, to: start, within: 28 / max(min(w, h), 1)) { dragging = i }
                        else if let r = CurveEditing.insert(pts, at: CGPoint(x: start.x, y: curve.value(at: start.x))) { pts = r.points; dragging = r.index; curve.points = pts }
                    }
                    if let i = dragging { curve.points = CurveEditing.move(sortedPoints(), index: i, to: p) }
                }
                .onEnded { _ in dragging = nil; onEnd() })
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { t in
                let pts = sortedPoints()
                if let i = CurveEditing.nearest(pts, to: toCurve(t.location), within: 28 / max(min(w, h), 1)) { curve.points = CurveEditing.remove(pts, index: i); onEnd() }
            })
        }
    }

    private func sortedPoints() -> [CGPoint] { curve.points.sorted { $0.x < $1.x } }
}
