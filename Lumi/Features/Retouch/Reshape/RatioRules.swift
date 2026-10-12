import CoreGraphics

/// Face position, rotation, symmetry, uneven-face fix, shading-based 3D contour and warp protection.
struct FaceRatio: Codable, Equatable {
    var shiftX = 0.0, shiftY = 0.0      // -1...1 move the face
    var rotate = 0.0                    // -1...1 turn the face in the picture plane
    var symmetry = 0.0                  // 0...1 level eyes and center the nose and mouth
    var unevenFix = 0.0                 // 0...1 even out left/right cheek and jaw width
    var shade3D = 0.0                   // 0...1 contour shadow plus highlight (shading, no warp)
    var protectFeatures = false         // eyes, nose and lips are not moved by other sliders
    var glassesLock = false             // the glasses band is not moved

    var isIdentity: Bool { self == FaceRatio() }
    var warps: Bool { shiftX != 0 || shiftY != 0 || rotate != 0 || symmetry > 0 || unevenFix > 0 }

    init() {}
    enum CodingKeys: String, CodingKey { case shiftX, shiftY, rotate, symmetry, unevenFix, shade3D, protectFeatures, glassesLock }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func v(_ k: CodingKeys) throws -> Double { try c.decodeIfPresent(Double.self, forKey: k) ?? 0 }
        shiftX = try v(.shiftX); shiftY = try v(.shiftY); rotate = try v(.rotate); symmetry = try v(.symmetry); unevenFix = try v(.unevenFix); shade3D = try v(.shade3D)
        protectFeatures = try c.decodeIfPresent(Bool.self, forKey: .protectFeatures) ?? false
        glassesLock = try c.decodeIfPresent(Bool.self, forKey: .glassesLock) ?? false
    }
}

enum RatioRules {
    static func strokes(for face: FaceInfo, _ raw: FaceRatio) -> [BrushStroke] {
        guard raw.warps else { return [] }
        func c(_ v: Double, _ lo: Double = -1) -> Float { Float(min(max(v, lo), 1)) }
        let faceW = Float(face.box.width)
        let contour = FaceReshape.points(face, "faceContour")
        let center = FaceReshape.center(contour) ?? CGPoint(x: face.box.midX, y: 1 - face.box.midY)
        let cx = Float(center.x), cy = Float(center.y)
        var out: [BrushStroke] = []

        if raw.shiftX != 0 || raw.shiftY != 0 {
            out.append(BrushStroke(kind: .push, x: cx, y: cy, radius: faceW * 0.8, strength: 1, dirX: c(raw.shiftX) * faceW * 0.08, dirY: c(raw.shiftY) * faceW * 0.08))
        }
        if raw.rotate != 0 {   // top goes one way, bottom the other
            let d = c(raw.rotate) * faceW * 0.06
            out.append(BrushStroke(kind: .push, x: cx, y: cy - faceW * 0.4, radius: faceW * 0.5, strength: 1, dirX: d, dirY: 0))
            out.append(BrushStroke(kind: .push, x: cx, y: cy + faceW * 0.4, radius: faceW * 0.5, strength: 1, dirX: -d, dirY: 0))
        }
        let l = FaceReshape.center(FaceReshape.points(face, "leftEye")), r = FaceReshape.center(FaceReshape.points(face, "rightEye"))
        if raw.symmetry > 0, let l, let r {
            let s = c(raw.symmetry, 0)
            let diff = Float(l.y - r.y) * 0.5 * s          // y-down: positive = left eye is lower
            out.append(BrushStroke(kind: .push, x: Float(l.x), y: Float(l.y), radius: faceW * 0.3, strength: 1, dirX: 0, dirY: -diff))
            out.append(BrushStroke(kind: .push, x: Float(r.x), y: Float(r.y), radius: faceW * 0.3, strength: 1, dirX: 0, dirY: diff))
            // nose and mouth toward the line between the eyes
            let mid = Float(l.x + r.x) / 2
            for region in ["nose", "outerLips"] {
                guard let p = FaceReshape.center(FaceReshape.points(face, region)) else { continue }
                out.append(BrushStroke(kind: .push, x: Float(p.x), y: Float(p.y), radius: faceW * 0.3, strength: 1, dirX: (mid - Float(p.x)) * s, dirY: 0))
            }
        }
        if raw.unevenFix > 0, contour.count >= 5 {
            // the wider half of the jaw is pulled in until both halves match
            let left = contour.filter { Float($0.x) < cx }, right = contour.filter { Float($0.x) >= cx }
            let lw = left.map { cx - Float($0.x) }.max() ?? 0, rw = right.map { Float($0.x) - cx }.max() ?? 0
            let gap = (lw - rw) * 0.5 * c(raw.unevenFix, 0)
            if let lp = left.min(by: { $0.x < $1.x }) { out.append(BrushStroke(kind: .push, x: Float(lp.x), y: Float(lp.y), radius: faceW * 0.3, strength: 1, dirX: -gap, dirY: 0)) }
            if let rp = right.max(by: { $0.x < $1.x }) { out.append(BrushStroke(kind: .push, x: Float(rp.x), y: Float(rp.y), radius: faceW * 0.3, strength: 1, dirX: -gap, dirY: 0)) }
        }
        return out
    }

    /// Makeup layer that carries the 3D shading.
    static func shading(_ r: FaceRatio) -> MakeupParams {
        var m = MakeupParams(); m.contour = min(max(r.shade3D, 0), 1); m.highlight = min(max(r.shade3D, 0), 1) * 0.8
        return m
    }
}

/// Areas other sliders must not move. All rects are image-normalized, y-down.
enum ProtectionZones {
    static func zones(_ face: FaceInfo, _ r: FaceRatio) -> [CGRect] {
        var z: [CGRect] = []
        func box(_ region: String, grow: CGFloat) -> CGRect? {
            let pts = FaceReshape.points(face, region)
            guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(), let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return nil }
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).insetBy(dx: -(x1 - x0) * grow, dy: -(x1 - x0) * grow)
        }
        if r.protectFeatures { z += ["leftEye", "rightEye", "nose", "outerLips"].compactMap { box($0, grow: 0.15) } }
        if r.glassesLock {
            let eyes = ["leftEye", "rightEye", "leftEyebrow", "rightEyebrow"].compactMap { box($0, grow: 0.2) }
            if let u = eyes.first { z.append(eyes.dropFirst().reduce(u) { $0.union($1) }) }
        }
        return z
    }

    /// Shrinks a stroke so it stops at the zones; drops it when it starts inside one.
    static func clip(_ s: BrushStroke, _ zones: [CGRect]) -> BrushStroke? {
        var s = s
        let p = CGPoint(x: CGFloat(s.x), y: CGFloat(s.y))
        for z in zones {
            if z.contains(p) { return nil }
            let dx = max(z.minX - p.x, 0, p.x - z.maxX), dy = max(z.minY - p.y, 0, p.y - z.maxY)
            s.radius = min(s.radius, Float((dx * dx + dy * dy).squareRoot()))
        }
        return s.radius > 0.005 ? s : nil
    }
}
