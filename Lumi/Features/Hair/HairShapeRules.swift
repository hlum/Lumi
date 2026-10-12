import CoreGraphics
import Foundation

/// Warp rules for hair shape, all in image-normalized, y-down space.
enum HairShapeRules {
    /// Volume (+ fuller crown, - flatter) and hairline (+ raise, - lower). Sliders are -1...1.
    static func strokes(faces: [FaceInfo], volume: Double, hairline: Double) -> [BrushStroke] {
        var out: [BrushStroke] = []
        let v = Float(min(max(volume, -1), 1)), h = Float(min(max(hairline, -1), 1))
        for f in faces {
            let box = MakeupRenderer.faceBox(f)
            let w = Float(box.width), ht = Float(box.height)
            if v != 0 {
                // the crown sits above the face; widen it outward (bloat) or flatten it (pinch)
                out.append(BrushStroke(kind: v > 0 ? .bloat : .pinch, x: Float(box.midX), y: Float(box.minY) - ht * 0.45, radius: w * 0.95, strength: abs(v) * 0.5))
            }
            if h != 0 {
                out.append(BrushStroke(kind: .push, x: Float(box.midX), y: Float(box.minY) - ht * 0.03, radius: w * 0.55, strength: 1, dirX: 0, dirY: -h * ht * 0.08))
            }
        }
        return out
    }
}
