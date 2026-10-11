import CoreImage
import CoreImage.CIFilterBuiltins

enum TransitionKind: String, Codable, CaseIterable { case none, fade, slideLeft, slideRight, wipe, zoom }

/// Frame math for a transition between the outgoing and incoming picture. `t` is progress 0...1.
/// This is a pure function so the same code serves preview, export and tests; a custom AVVideoCompositing calls it per frame.
enum Transitions {
    static let defaultDuration = 0.5

    static func frame(_ kind: TransitionKind, from a: CIImage, to b: CIImage, progress raw: Double) -> CIImage {
        let t = min(max(raw, 0), 1), e = a.extent
        switch kind {
        case .none: return t < 1 ? a : b
        case .fade:
            let f = CIFilter.dissolveTransition(); f.inputImage = a; f.targetImage = b; f.time = Float(t)
            return f.outputImage?.cropped(to: e) ?? a
        case .slideLeft, .slideRight:
            let dir: CGFloat = kind == .slideLeft ? -1 : 1               // the old picture leaves toward `dir`
            let off = dir * e.width * CGFloat(t)
            let old = a.transformed(by: CGAffineTransform(translationX: off, y: 0))
            let new = b.transformed(by: CGAffineTransform(translationX: off - dir * e.width, y: 0))
            return old.composited(over: new).cropped(to: e)
        case .wipe:
            let x = e.minX + e.width * CGFloat(t)
            let revealed = b.cropped(to: CGRect(x: e.minX, y: e.minY, width: max(x - e.minX, 0), height: e.height))
            return revealed.composited(over: a).cropped(to: e)
        case .zoom:
            // outgoing zooms in and fades; incoming settles from slightly large
            let sa = 1 + 0.5 * CGFloat(t), sb = 1.25 - 0.25 * CGFloat(t)
            func scaled(_ i: CIImage, _ s: CGFloat) -> CIImage {
                i.transformed(by: CGAffineTransform(translationX: -e.midX, y: -e.midY).scaledBy(x: s, y: s).translatedBy(x: e.midX / s, y: e.midY / s)).cropped(to: e)
            }
            let f = CIFilter.dissolveTransition(); f.inputImage = scaled(a, sa); f.targetImage = scaled(b, sb); f.time = Float(t)
            return f.outputImage?.cropped(to: e) ?? a
        }
    }

    /// Where the overlap sits when clip `i` hands over to clip `i+1`: the last `duration` seconds of clip i (clamped to half of either clip).
    static func overlap(clipA: Double, clipB: Double, requested: Double) -> Double {
        max(0, min(requested, clipA / 2, clipB / 2))
    }

    /// Progress for a transition that runs over `duration` seconds starting at `start`.
    static func progress(at time: Double, start: Double, duration: Double) -> Double {
        guard duration > 0 else { return time >= start ? 1 : 0 }
        return min(max((time - start) / duration, 0), 1)
    }
}
