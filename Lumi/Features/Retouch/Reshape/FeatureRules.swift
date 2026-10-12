import CoreGraphics

/// Eye, nose, mouth, brow and face-outline sliders beyond the basic ones in `FaceReshapeParams`. Each is -1...1, 0 = off.
struct FeatureShape: Codable, Equatable {
    // eyes
    var eyeDistance = 0.0, eyeHeight = 0.0, eyeTilt = 0.0, eyeInner = 0.0, eyeOuter = 0.0, eyeLids = 0.0, eyeSocket = 0.0
    // nose
    var noseWings = 0.0, noseBridge = 0.0, noseTip = 0.0, noseLength = 0.0
    // mouth
    var mouthWidth = 0.0, mouthFullness = 0.0, mouthSmile = 0.0, mouthCupid = 0.0, mouthProtrusion = 0.0, mouthPout = 0.0
    // brows
    var browSpacing = 0.0, browPeak = 0.0, browLift = 0.0
    // face outline
    var vShape = 0.0, cheekbones = 0.0, forehead = 0.0

    var isIdentity: Bool { self == FeatureShape() }

    enum Key: String, CaseIterable, Codable {
        case eyeDistance, eyeHeight, eyeTilt, eyeInner, eyeOuter, eyeLids, eyeSocket
        case noseWings, noseBridge, noseTip, noseLength
        case mouthWidth, mouthFullness, mouthSmile, mouthCupid, mouthProtrusion, mouthPout
        case browSpacing, browPeak, browLift
        case vShape, cheekbones, forehead

        var path: WritableKeyPath<FeatureShape, Double> {
            switch self {
            case .eyeDistance: \.eyeDistance; case .eyeHeight: \.eyeHeight; case .eyeTilt: \.eyeTilt; case .eyeInner: \.eyeInner; case .eyeOuter: \.eyeOuter; case .eyeLids: \.eyeLids; case .eyeSocket: \.eyeSocket
            case .noseWings: \.noseWings; case .noseBridge: \.noseBridge; case .noseTip: \.noseTip; case .noseLength: \.noseLength
            case .mouthWidth: \.mouthWidth; case .mouthFullness: \.mouthFullness; case .mouthSmile: \.mouthSmile; case .mouthCupid: \.mouthCupid; case .mouthProtrusion: \.mouthProtrusion; case .mouthPout: \.mouthPout
            case .browSpacing: \.browSpacing; case .browPeak: \.browPeak; case .browLift: \.browLift
            case .vShape: \.vShape; case .cheekbones: \.cheekbones; case .forehead: \.forehead
            }
        }
    }

    subscript(key: Key) -> Double {
        get { self[keyPath: key.path] }
        set { self[keyPath: key.path] = min(max(newValue, -1), 1) }
    }

    init() {}
    init(from decoder: Decoder) throws {
        struct K: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { nil } }
        let c = try decoder.container(keyedBy: K.self)
        for k in Key.allCases { self[keyPath: k.path] = try c.decodeIfPresent(Double.self, forKey: K(stringValue: k.rawValue)!) ?? 0 }
    }
    func encode(to encoder: Encoder) throws {
        struct K: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { nil } }
        var c = encoder.container(keyedBy: K.self)
        for k in Key.allCases { try c.encode(self[keyPath: k.path], forKey: K(stringValue: k.rawValue)!) }
    }
}

enum FeatureRules {
    /// Warp strokes for the feature sliders of one face. Directions follow the picture: +x right, +y down.
    static func strokes(for face: FaceInfo, _ p: FeatureShape) -> [BrushStroke] {
        guard !p.isIdentity else { return [] }
        func a(_ v: Double) -> Float { Float(min(max(v, -1), 1)) }
        let faceW = Float(face.box.width)
        var out: [BrushStroke] = []
        func push(_ c: CGPoint, r: Float, dx: Float, dy: Float) { out.append(BrushStroke(kind: .push, x: Float(c.x), y: Float(c.y), radius: r, strength: 1, dirX: dx, dirY: dy)) }
        func zoom(_ c: CGPoint, r: Float, amount: Float) { if amount != 0 { out.append(BrushStroke(kind: amount > 0 ? .bloat : .pinch, x: Float(c.x), y: Float(c.y), radius: r, strength: abs(amount))) } }

        // --- eyes: left/right by position, so it does not matter which one Vision calls "left"
        let eyes = ["leftEye", "rightEye"].map { FaceReshape.points(face, $0) }.filter { !$0.isEmpty }.sorted { (FaceReshape.center($0)?.x ?? 0) < (FaceReshape.center($1)?.x ?? 0) }
        for (i, pts) in eyes.enumerated() {
            guard let c = FaceReshape.center(pts) else { continue }
            let w = Float(FaceReshape.width(pts)), side: Float = i == 0 ? -1 : 1            // -1 = left of the picture
            let outer = pts.max { side * Float($0.x) < side * Float($1.x) }!, inner = pts.min { side * Float($0.x) < side * Float($1.x) }!
            let top = pts.min { $0.y < $1.y }!
            if p.eyeDistance != 0 { push(c, r: w * 1.2, dx: side * a(p.eyeDistance) * w * 0.35, dy: 0) }
            if p.eyeHeight != 0 { push(c, r: w * 1.2, dx: 0, dy: -a(p.eyeHeight) * w * 0.25) }
            if p.eyeTilt != 0 {          // + lifts the outer corner and drops the inner one
                push(outer, r: w * 0.6, dx: 0, dy: -a(p.eyeTilt) * w * 0.2); push(inner, r: w * 0.6, dx: 0, dy: a(p.eyeTilt) * w * 0.2)
            }
            if p.eyeOuter != 0 { push(outer, r: w * 0.55, dx: side * a(p.eyeOuter) * w * 0.25, dy: 0) }
            if p.eyeInner != 0 { push(inner, r: w * 0.55, dx: -side * a(p.eyeInner) * w * 0.25, dy: 0) }
            if p.eyeLids != 0 { push(top, r: w * 0.6, dx: 0, dy: -a(p.eyeLids) * w * 0.22) }
            if p.eyeSocket != 0 { zoom(CGPoint(x: c.x, y: top.y - CGFloat(w) * 0.25), r: w * 0.9, amount: -a(p.eyeSocket) * 0.5) }
        }

        // --- nose
        let nose = FaceReshape.points(face, "nose")
        if let c = FaceReshape.center(nose), !nose.isEmpty {
            let w = Float(FaceReshape.width(nose))
            let low = nose.max { $0.y < $1.y }!, high = nose.min { $0.y < $1.y }!
            let left = nose.min { $0.x < $1.x }!, right = nose.max { $0.x < $1.x }!
            if p.noseWings != 0 { push(left, r: w * 0.7, dx: a(p.noseWings) * w * 0.3, dy: 0); push(right, r: w * 0.7, dx: -a(p.noseWings) * w * 0.3, dy: 0) }
            if p.noseBridge != 0 { push(CGPoint(x: c.x - CGFloat(w) * 0.2, y: high.y), r: w * 0.6, dx: a(p.noseBridge) * w * 0.2, dy: 0); push(CGPoint(x: c.x + CGFloat(w) * 0.2, y: high.y), r: w * 0.6, dx: -a(p.noseBridge) * w * 0.2, dy: 0) }
            if p.noseTip != 0 { zoom(low, r: w * 0.6, amount: -a(p.noseTip) * 0.5) }
            if p.noseLength != 0 { push(low, r: w * 1.1, dx: 0, dy: a(p.noseLength) * w * 0.3) }
        }

        // --- mouth
        let lips = FaceReshape.points(face, "outerLips")
        if let c = FaceReshape.center(lips), !lips.isEmpty {
            let w = Float(FaceReshape.width(lips))
            let l = lips.min { $0.x < $1.x }!, r = lips.max { $0.x < $1.x }!
            let top = lips.min { $0.y < $1.y }!, bottom = lips.max { $0.y < $1.y }!
            if p.mouthWidth != 0 { push(l, r: w * 0.5, dx: -a(p.mouthWidth) * w * 0.2, dy: 0); push(r, r: w * 0.5, dx: a(p.mouthWidth) * w * 0.2, dy: 0) }
            if p.mouthFullness != 0 { zoom(top, r: w * 0.5, amount: a(p.mouthFullness) * 0.5); zoom(bottom, r: w * 0.5, amount: a(p.mouthFullness) * 0.5) }
            if p.mouthSmile != 0 { push(l, r: w * 0.45, dx: 0, dy: -a(p.mouthSmile) * w * 0.18); push(r, r: w * 0.45, dx: 0, dy: -a(p.mouthSmile) * w * 0.18) }
            if p.mouthCupid != 0 { push(top, r: w * 0.3, dx: 0, dy: -a(p.mouthCupid) * w * 0.12) }
            if p.mouthProtrusion != 0 { zoom(c, r: w * 0.8, amount: a(p.mouthProtrusion) * 0.4) }
            if p.mouthPout != 0 { zoom(bottom, r: w * 0.55, amount: a(p.mouthPout) * 0.6) }
        }

        // --- brows
        let brows = ["leftEyebrow", "rightEyebrow"].map { FaceReshape.points(face, $0) }.filter { !$0.isEmpty }.sorted { (FaceReshape.center($0)?.x ?? 0) < (FaceReshape.center($1)?.x ?? 0) }
        for (i, pts) in brows.enumerated() {
            guard let c = FaceReshape.center(pts) else { continue }
            let w = Float(FaceReshape.width(pts)), side: Float = i == 0 ? -1 : 1
            let outer = pts.max { side * Float($0.x) < side * Float($1.x) }!
            if p.browSpacing != 0 { push(c, r: w * 0.9, dx: side * a(p.browSpacing) * w * 0.25, dy: 0) }
            if p.browPeak != 0 { push(CGPoint(x: c.x + CGFloat(side) * CGFloat(w) * 0.15, y: c.y), r: w * 0.35, dx: 0, dy: -a(p.browPeak) * w * 0.2) }
            if p.browLift != 0 { push(outer, r: w * 0.5, dx: 0, dy: -a(p.browLift) * w * 0.25) }
        }

        // --- face outline
        let contour = FaceReshape.points(face, "faceContour")
        if contour.count >= 5 {
            let mid = FaceReshape.center(contour)?.x ?? face.box.midX
            let lo = contour.map(\.y).max()!, hi = contour.map(\.y).min()!
            if p.vShape != 0 {      // + narrows the lower jaw toward a pointed chin
                for c in contour where (c.y - hi) > (lo - hi) * 0.5 {
                    let side: Float = c.x < mid ? 1 : -1
                    let k = Float((c.y - hi) / (lo - hi))
                    push(c, r: faceW * 0.28, dx: side * a(p.vShape) * faceW * 0.07 * k, dy: 0)
                }
            }
            if p.cheekbones != 0 {  // + slims the cheekbones inward
                for c in contour where (c.y - hi) > (lo - hi) * 0.2 && (c.y - hi) < (lo - hi) * 0.55 {
                    push(c, r: faceW * 0.3, dx: (c.x < mid ? 1 : -1) * a(p.cheekbones) * faceW * 0.05, dy: 0)
                }
            }
            if p.forehead != 0, let top = FaceReshape.points(face, "leftEyebrow").first {
                push(CGPoint(x: mid, y: top.y - CGFloat(faceW) * 0.2), r: faceW * 0.5, dx: 0, dy: -a(p.forehead) * faceW * 0.08)
            }
        }
        return out
    }
}
