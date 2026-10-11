import CoreGraphics
import Foundation

/// Turns a finger drag into warp strokes: "push" moves pixels along the drag (slim), "bloat" and "pinch" act where you press and move.
struct WarpBrush: Equatable {
    var kind = BrushStroke.Kind.push
    var size = 0.12              // radius as a fraction of the image width
    var strength = 0.5           // 0...1

    /// Minimum finger travel (fraction of the brush radius) before another stroke is added, so a drag stays smooth but cheap.
    static let spacing = 0.25

    /// Points are normalized image coordinates (y-down). Returns the strokes for the whole drag.
    func strokes(for path: [CGPoint]) -> [BrushStroke] {
        guard let first = path.first else { return [] }
        let r = Float(min(max(size, 0.02), 0.5)), s = Float(min(max(strength, 0), 1))
        guard kind == .push else {
            // bloat / pinch: one stroke per spaced point along the drag
            return spaced(path).map { BrushStroke(kind: kind, x: Float($0.x), y: Float($0.y), radius: r, strength: s * 0.35) }
        }
        var out: [BrushStroke] = []
        var last = first
        for p in spaced(path).dropFirst() {
            let dx = Float(p.x - last.x), dy = Float(p.y - last.y)
            out.append(BrushStroke(kind: .push, x: Float(last.x), y: Float(last.y), radius: r, strength: s, dirX: dx, dirY: dy))
            last = p
        }
        return out
    }

    private func spaced(_ path: [CGPoint]) -> [CGPoint] {
        guard let first = path.first else { return [] }
        let minDist = CGFloat(max(size, 0.02) * Self.spacing)
        var out = [first]
        for p in path.dropFirst() where hypot(p.x - out.last!.x, p.y - out.last!.y) >= minDist { out.append(p) }
        if let l = path.last, l != out.last, hypot(l.x - out.last!.x, l.y - out.last!.y) > minDist / 4 { out.append(l) }
        return out
    }
}
