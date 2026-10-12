import CoreGraphics
import Foundation

/// Face shape sliders as landmark moves for the rigid MLS warp: the outline and features go exactly where the slider says,
/// every feature that isn't being edited is pinned, and a ring of pins around the head keeps the background still.
enum FaceHandles {
    /// What is left for the brush rules once this file has taken its sliders (cheek volume stays a radial "fullness").
    static func remainingReshape(_ r: FaceReshapeParams) -> FaceReshapeParams {
        var out = FaceReshapeParams(); out.cheekVolume = r.cheekVolume; return out
    }
    static func remainingShape(_ s: FeatureShape) -> FeatureShape {
        var out = s; out.vShape = 0; out.cheekbones = 0; return out
    }
    static func isIdentity(_ r: FaceReshapeParams, _ s: FeatureShape) -> Bool {
        r.jawSlim == 0 && r.chinLength == 0 && r.eyeSize == 0 && r.noseSlim == 0 && r.mouthSize == 0 && r.faceWidth == 0 && r.lift == 0 && s.vShape == 0 && s.cheekbones == 0
    }

    private static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t)
    }

    static func handles(for face: FaceInfo, reshape raw: FaceReshapeParams, shape rawShape: FeatureShape, ratio: FaceRatio, aspect: Double) -> [WarpHandle] {
        var r = raw; r.clamp()
        let s = rawShape
        guard !isIdentity(r, s) else { return [] }
        func pts(_ n: String) -> [CGPoint] { FaceReshape.points(face, n) }
        let contour = pts("faceContour")
        guard contour.count >= 5, let top = contour.map(\.y).min(), let bottom = contour.map(\.y).max() else { return [] }
        let mid = (contour.map(\.x).min()! + contour.map(\.x).max()!) / 2
        let faceW = Double(contour.map(\.x).max()! - contour.map(\.x).min()!), faceH = Double(face.box.height)
        func c(_ v: Double) -> Double { min(max(v, -1), 1) }
        var out: [WarpHandle] = []

        // outline: each contour point gets one target that sums every outline slider
        for p in contour {
            let t = Double((p.y - top) / max(bottom - top, 1e-6))          // 0 at the ears, 1 at the chin
            let toMid = Double(mid - p.x)
            var dx = 0.0, dy = 0.0
            dx += toMid * 0.14 * c(r.jawSlim) * smooth(0.3, 0.7, t)                     // jaw: lower outline in
            dx += toMid * 0.10 * c(r.faceWidth)                                           // width: whole outline in
            dx += toMid * 0.16 * c(s.vShape) * smooth(0.35, 0.8, t)                       // V: jaw angles in, chin narrows
            dy += 0.03 * faceH * c(s.vShape) * smooth(0.8, 1, t)
            dx += toMid * 0.09 * c(s.cheekbones) * (1 - smooth(0.25, 0.45, t))            // cheekbones: upper outline in
            dy += 0.10 * faceH * c(r.chinLength) * smooth(0.75, 1, t)                     // chin: longer or shorter
            dy -= 0.04 * faceH * c(r.lift) * smooth(0.35, 0.8, t)                         // lift: lower outline up
            out.append(WarpHandle(from: p, to: CGPoint(x: Double(p.x) + dx, y: Double(p.y) + dy)))
        }

        // features: scaled about their own centre when edited, pinned otherwise
        func scaled(_ ps: [CGPoint], by k: Double, xOnly: Bool = false) -> [WarpHandle] {
            guard let ctr = FaceReshape.center(ps) else { return [] }
            return ps.map { WarpHandle(from: $0, to: CGPoint(x: Double(ctr.x) + Double($0.x - ctr.x) * k, y: xOnly ? Double($0.y) : Double(ctr.y) + Double($0.y - ctr.y) * k)) }
        }
        for eye in ["leftEye", "rightEye"] {
            let e = pts(eye) + pts(eye == "leftEye" ? "leftPupil" : "rightPupil")
            out += r.eyeSize != 0 ? scaled(e, by: 1 + 0.22 * c(r.eyeSize)) : e.map(WarpHandle.pin)
        }
        out += (pts("leftEyebrow") + pts("rightEyebrow")).map(WarpHandle.pin)
        let nose = pts("nose") + pts("noseCrest")
        out += r.noseSlim != 0 ? scaled(nose, by: 1 - 0.2 * c(r.noseSlim), xOnly: true) : nose.map(WarpHandle.pin)
        let lips = pts("outerLips") + pts("innerLips")
        out += r.mouthSize != 0 ? scaled(lips, by: 1 + 0.15 * c(r.mouthSize)) : lips.map(WarpHandle.pin)

        // glasses lock: a pinned band across the face at eye height
        if ratio.glassesLock, let l = FaceReshape.center(pts("leftEye")), let rr = FaceReshape.center(pts("rightEye")) {
            let y = (l.y + rr.y) / 2, x0 = contour.map(\.x).min()!, x1 = contour.map(\.x).max()!
            for i in 0...8 { out.append(.pin(CGPoint(x: x0 + (x1 - x0) * CGFloat(i) / 8, y: y))) }
        }

        // the background holds still beyond a ring around the head
        let ctr = CGPoint(x: Double(mid), y: Double(top + bottom) / 2 - faceH * 0.1)
        out += MLSWarp.ring(around: ctr, radius: max(faceW * aspect, faceH) * 1.0, aspect: aspect, count: 24)
        return out
    }
}
