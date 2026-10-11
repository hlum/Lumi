import CoreGraphics
import Foundation

/// Slider values, each -1...1 (0 = off).
struct FaceReshapeParams: Codable, Equatable {
    var jawSlim = 0.0, chinLength = 0.0, eyeSize = 0.0, noseSlim = 0.0, mouthSize = 0.0, faceWidth = 0.0
    var cheekVolume = 0.0, lift = 0.0

    var isIdentity: Bool { self == FaceReshapeParams() }

    init() {}
    enum CodingKeys: String, CodingKey { case jawSlim, chinLength, eyeSize, noseSlim, mouthSize, faceWidth, cheekVolume, lift }
    init(jawSlim: Double = 0, chinLength: Double = 0, eyeSize: Double = 0, noseSlim: Double = 0, mouthSize: Double = 0, faceWidth: Double = 0, cheekVolume: Double = 0, lift: Double = 0) {
        self.jawSlim = jawSlim; self.chinLength = chinLength; self.eyeSize = eyeSize; self.noseSlim = noseSlim; self.mouthSize = mouthSize; self.faceWidth = faceWidth; self.cheekVolume = cheekVolume; self.lift = lift
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d(_ k: CodingKeys) throws -> Double { try c.decodeIfPresent(Double.self, forKey: k) ?? 0 }
        self.init(jawSlim: try d(.jawSlim), chinLength: try d(.chinLength), eyeSize: try d(.eyeSize), noseSlim: try d(.noseSlim), mouthSize: try d(.mouthSize), faceWidth: try d(.faceWidth), cheekVolume: try d(.cheekVolume), lift: try d(.lift))
    }
    mutating func clamp() {
        func c(_ v: inout Double) { v = min(max(v, -1), 1) }
        c(&jawSlim); c(&chinLength); c(&eyeSize); c(&noseSlim); c(&mouthSize); c(&faceWidth); c(&cheekVolume); c(&lift)
    }
}

/// Turns face landmarks plus slider values into brush strokes for the warp engine.
/// One small rule per slider; all geometry is in image-normalized space, origin top-left.
enum FaceReshape {
    /// Landmark region as image-normalized, y-down points. Vision gives points relative to the face box, y-up.
    static func points(_ face: FaceInfo, _ region: String) -> [CGPoint] {
        (face.landmarks[region] ?? []).map {
            CGPoint(x: face.box.minX + $0.x * face.box.width, y: 1 - (face.box.minY + $0.y * face.box.height))
        }
    }

    static func center(_ pts: [CGPoint]) -> CGPoint? {
        guard !pts.isEmpty else { return nil }
        return CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
    }

    static func width(_ pts: [CGPoint]) -> CGFloat {
        guard let lo = pts.map(\.x).min(), let hi = pts.map(\.x).max() else { return 0 }
        return hi - lo
    }

    static func strokes(for face: FaceInfo, params raw: FaceReshapeParams) -> [BrushStroke] {
        var p = raw; p.clamp()
        guard !p.isIdentity else { return [] }
        var out: [BrushStroke] = []
        let faceW = Float(face.box.width)
        let contour = points(face, "faceContour")
        let mid = Float(center(contour)?.x ?? face.box.midX)

        // Jaw slim: push the lower contour points toward the face's vertical midline.
        if p.jawSlim != 0, contour.count >= 5 {
            let lowest = contour.map(\.y).max()!, highest = contour.map(\.y).min()!
            for c in contour where (c.y - highest) > (lowest - highest) * 0.35 {
                let side: Float = Float(c.x) < mid ? 1 : -1
                out.append(BrushStroke(kind: .push, x: Float(c.x), y: Float(c.y), radius: faceW * 0.30, strength: 1,
                                       dirX: side * Float(p.jawSlim) * faceW * 0.06, dirY: 0))
            }
        }
        // Face width: same idea, but for the whole contour, gentler.
        if p.faceWidth != 0, contour.count >= 5 {
            for c in contour {
                let side: Float = Float(c.x) < mid ? 1 : -1
                out.append(BrushStroke(kind: .push, x: Float(c.x), y: Float(c.y), radius: faceW * 0.35, strength: 1,
                                       dirX: side * Float(p.faceWidth) * faceW * 0.04, dirY: 0))
            }
        }
        // Chin length: push the lowest contour point down (positive) or up.
        if p.chinLength != 0, let chin = contour.max(by: { $0.y < $1.y }) {
            out.append(BrushStroke(kind: .push, x: Float(chin.x), y: Float(chin.y), radius: faceW * 0.35, strength: 1,
                                   dirX: 0, dirY: Float(p.chinLength) * faceW * 0.07))
        }
        // Eyes: bloat (or pinch) at each eye center, sized by eye width.
        if p.eyeSize != 0 {
            for region in ["leftEye", "rightEye"] {
                let pts = points(face, region)
                guard let c = center(pts), width(pts) > 0 else { continue }
                out.append(BrushStroke(kind: p.eyeSize > 0 ? .bloat : .pinch, x: Float(c.x), y: Float(c.y),
                                       radius: Float(width(pts)) * 1.3, strength: Float(abs(p.eyeSize)) * 0.5))
            }
        }
        // Nose: pinch at the nose center.
        if p.noseSlim != 0 {
            let pts = points(face, "nose")
            if let c = center(pts), width(pts) > 0 {
                out.append(BrushStroke(kind: p.noseSlim > 0 ? .pinch : .bloat, x: Float(c.x), y: Float(c.y),
                                       radius: Float(width(pts)) * 1.4, strength: Float(abs(p.noseSlim)) * 0.4))
            }
        }
        // Mouth: bloat (bigger) or pinch (smaller) at the outer lips.
        if p.mouthSize != 0 {
            let pts = points(face, "outerLips")
            if let c = center(pts), width(pts) > 0 {
                out.append(BrushStroke(kind: p.mouthSize > 0 ? .bloat : .pinch, x: Float(c.x), y: Float(c.y),
                                       radius: Float(width(pts)) * 1.2, strength: Float(abs(p.mouthSize)) * 0.4))
            }
        }
        // Cheek volume: bloat (fuller) or pinch (slimmer) on each cheek, found under the eyes toward the ear.
        if p.cheekVolume != 0 {
            for spot in MakeupRenderer.blushSpots(face, style: .round) {
                out.append(BrushStroke(kind: p.cheekVolume > 0 ? .bloat : .pinch, x: Float(spot.center.x), y: Float(spot.center.y + spot.radius * 0.3),
                                       radius: Float(spot.radius) * 1.6, strength: Float(abs(p.cheekVolume)) * 0.45))
            }
        }
        // Lift: nudge the cheeks and jawline up and slightly outward (a subtle face-lift).
        if p.lift != 0, contour.count >= 5 {
            let lowest = contour.map(\.y).max()!, highest = contour.map(\.y).min()!
            for c in contour where (c.y - highest) > (lowest - highest) * 0.45 {
                let side: Float = Float(c.x) < mid ? -1 : 1
                out.append(BrushStroke(kind: .push, x: Float(c.x), y: Float(c.y), radius: faceW * 0.3, strength: 1, dirX: side * Float(p.lift) * faceW * 0.015, dirY: -Float(p.lift) * faceW * 0.05))
            }
        }
        return out
    }

    /// Strokes for every selected person, in order.
    static func strokes(for faces: [FaceInfo], params: FaceReshapeParams) -> [BrushStroke] {
        faces.flatMap { strokes(for: $0, params: params) }
    }
}
