import CoreGraphics
import CoreImage
import Vision

/// Per-frame camera motion relative to the previous frame, in pixels and radians.
struct FrameMotion: Equatable { var dx = 0.0, dy = 0.0, rotation = 0.0 }

enum Stabilizer {
    /// Camera path: running sum of the frame-to-frame motion.
    static func path(_ motion: [FrameMotion]) -> [FrameMotion] {
        var acc = FrameMotion(); var out: [FrameMotion] = []
        for m in motion { acc.dx += m.dx; acc.dy += m.dy; acc.rotation += m.rotation; out.append(acc) }
        return out
    }

    /// Moving average with `radius` frames each side (shorter at the ends, so the first and last frames still move correctly).
    static func smooth(_ p: [FrameMotion], radius: Int) -> [FrameMotion] {
        guard radius > 0, !p.isEmpty else { return p }
        return p.indices.map { i in
            let r = max(0, i - radius)...min(p.count - 1, i + radius), n = Double(r.count)
            return FrameMotion(dx: p[r].reduce(0) { $0 + $1.dx } / n, dy: p[r].reduce(0) { $0 + $1.dy } / n, rotation: p[r].reduce(0) { $0 + $1.rotation } / n)
        }
    }

    /// What to apply to each frame to move it from the shaky path onto the smooth one.
    static func corrections(_ motion: [FrameMotion], radius: Int = 15) -> [FrameMotion] {
        let raw = path(motion), smoothed = smooth(raw, radius: radius)
        return zip(raw, smoothed).map { FrameMotion(dx: $1.dx - $0.dx, dy: $1.dy - $0.dy, rotation: $1.rotation - $0.rotation) }
    }

    /// Zoom that hides the empty edges the corrections would reveal.
    static func cropScale(_ c: [FrameMotion], frame: CGSize) -> Double {
        guard frame.width > 0, frame.height > 0 else { return 1 }
        let rotationPx = c.map { abs($0.rotation) * Double(max(frame.width, frame.height)) / 2 }
        let mx = zip(c, rotationPx).map { abs($0.dx) + $1 }.max() ?? 0, my = zip(c, rotationPx).map { abs($0.dy) + $1 }.max() ?? 0
        return 1 + 2 * max(mx / Double(frame.width), my / Double(frame.height))
    }

    /// Moves the frame by the correction, then zooms about the center by `scale`.
    static func apply(_ c: FrameMotion, scale: Double, to frame: CIImage) -> CIImage {
        let e = frame.extent
        let t = CGAffineTransform(translationX: -e.midX, y: -e.midY).concatenating(CGAffineTransform(rotationAngle: CGFloat(-c.rotation)))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale)).concatenating(CGAffineTransform(translationX: e.midX + c.dx, y: e.midY - c.dy))
        return frame.clampedToExtent().transformed(by: t).cropped(to: e)
    }

    private static let ctx = CIContext()

    /// How far `b` moved relative to `a` (Vision translational registration). dy is y-down like the picture.
    static func motion(from a: CIImage, to b: CIImage) -> FrameMotion? {
        // render both first: Vision reads lazily evaluated filter graphs unreliably
        guard let ca = ctx.createCGImage(a, from: a.extent), let cb = ctx.createCGImage(b, from: b.extent) else { return nil }
        let req = VNTranslationalImageRegistrationRequest(targetedCGImage: ca)
        guard (try? VNImageRequestHandler(cgImage: cb).perform([req])) != nil, let r = req.results?.first as? VNImageTranslationAlignmentObservation else { return nil }
        let t = r.alignmentTransform
        return FrameMotion(dx: -t.tx, dy: t.ty, rotation: 0)
    }
}
