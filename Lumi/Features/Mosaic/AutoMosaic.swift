import CoreGraphics
import Foundation

/// Region selection for auto-mosaic. All rects are normalized, origin bottom-left (Vision space).
enum AutoMosaic {
    /// Faces to cover, padded and clamped to the image; faces inside `protected` (the chosen subject) are skipped.
    static func faceRegions(_ faces: [FaceInfo], padding: CGFloat = 0.15, skipping protected: [CGRect] = []) -> [CGRect] {
        faces.map(\.box).filter { f in !protected.contains { $0.contains(CGPoint(x: f.midX, y: f.midY)) } }
            .map { clamp($0.insetBy(dx: -$0.width * padding, dy: -$0.height * padding)) }
    }

    /// Chat screenshots: names are text lines in the left column of a row; avatars are the square-ish areas at
    /// the row's left edge. Heuristic: text boxes whose left edge is in the left `leftZone` of the image and
    /// are short (names, not messages) get covered, plus an avatar square to their left.
    static func chatRegions(textBoxes: [CGRect], leftZone: CGFloat = 0.45, maxNameWidth: CGFloat = 0.35, imageAspect: CGFloat) -> [CGRect] {
        var out: [CGRect] = []
        for t in textBoxes where t.minX < leftZone && t.width <= maxNameWidth && t.height > 0 {
            out.append(clamp(t.insetBy(dx: -0.005, dy: -0.003)))
            let side = t.height * 3                                   // avatar ≈ 3 text lines tall
            let w = side / max(imageAspect, 0.01)                     // normalize to width
            let x = t.minX - w - 0.01
            if x >= 0 { out.append(clamp(CGRect(x: x, y: t.midY - side / 2, width: w, height: side))) }
        }
        return merge(out)
    }

    static func clamp(_ r: CGRect) -> CGRect { r.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)) }

    /// Merges rects that overlap so the same area isn't pixelated twice.
    static func merge(_ rects: [CGRect]) -> [CGRect] {
        var out = rects.filter { !$0.isNull && !$0.isEmpty }
        var changed = true
        while changed {
            changed = false
            outer: for i in out.indices { for j in out.indices where j > i && out[i].intersects(out[j]) {
                out[i] = out[i].union(out[j]); out.remove(at: j); changed = true; break outer
            } }
        }
        return out
    }
}
