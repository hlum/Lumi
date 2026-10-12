import CoreGraphics
import Foundation

/// Slider values, each -1...1 (0 = off).
struct BodyReshapeParams: Codable, Equatable {
    var waist = 0.0, legLength = 0.0, legSlim = 0.0, armSlim = 0.0, shoulder = 0.0, headSize = 0.0, hips = 0.0
    var thighs = 0.0, calves = 0.0, legStraighten = 0.0

    var isIdentity: Bool { self == BodyReshapeParams() }
    mutating func clamp() {
        func c(_ v: inout Double) { v = min(max(v, -1), 1) }
        c(&waist); c(&legLength); c(&legSlim); c(&armSlim); c(&shoulder); c(&headSize); c(&hips); c(&thighs); c(&calves); c(&legStraighten)
    }

    enum Key: String, CaseIterable, Codable {
        case waist, legLength, legSlim, armSlim, shoulder, headSize, hips, thighs, calves, legStraighten
        var path: WritableKeyPath<BodyReshapeParams, Double> {
            switch self {
            case .waist: \.waist; case .legLength: \.legLength; case .legSlim: \.legSlim; case .armSlim: \.armSlim; case .shoulder: \.shoulder
            case .headSize: \.headSize; case .hips: \.hips; case .thighs: \.thighs; case .calves: \.calves; case .legStraighten: \.legStraighten
            }
        }
    }
}

extension BodyReshapeParams {
    init(from decoder: Decoder) throws {
        struct K: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { nil } }
        let c = try decoder.container(keyedBy: K.self)
        self.init()
        for k in Key.allCases { self[keyPath: k.path] = try c.decodeIfPresent(Double.self, forKey: K(stringValue: k.rawValue)!) ?? 0 }
    }
    func encode(to encoder: Encoder) throws {
        struct K: CodingKey { var stringValue: String; var intValue: Int? { nil }; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { nil } }
        var c = encoder.container(keyedBy: K.self)
        for k in Key.allCases { try c.encode(self[keyPath: k.path], forKey: K(stringValue: k.rawValue)!) }
    }
}

/// Pose joints (image-normalized, y-down) -> warp strokes. One small rule per slider.
enum BodyReshape {
    /// Vision joints are normalized with a bottom-left origin; flip to y-down.
    static func joints(_ pose: [String: CGPoint]) -> [String: CGPoint] {
        pose.mapValues { CGPoint(x: $0.x, y: 1 - $0.y) }
    }

    private static func mid(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
        guard let a, let b else { return nil }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Pushes the two edges of a body part toward its center line. `a` and `b` are the edges, in any order (Vision's "left" is the subject's left, which is usually the image's right).
    private static func squeeze(_ a: CGPoint, _ b: CGPoint, amount: Double, radius: Float, out: inout [BrushStroke], reach: Double = 0.06) {
        let (l, r) = a.x <= b.x ? (a, b) : (b, a)
        let push = Float(amount) * Float(r.x - l.x) * Float(reach) * 4
        out.append(BrushStroke(kind: .push, x: Float(l.x), y: Float(l.y), radius: radius, strength: 1, dirX: push, dirY: 0))
        out.append(BrushStroke(kind: .push, x: Float(r.x), y: Float(r.y), radius: radius, strength: 1, dirX: -push, dirY: 0))
    }

    /// `silhouette` gives the body's left and right edge (image-normalized x) at a height (y-down) when the person mask can tell; otherwise the edges are estimated from the joints.
    static func strokes(pose raw: [String: CGPoint], params raw2: BodyReshapeParams, silhouette: ((Double) -> (Double, Double)?)? = nil) -> [BrushStroke] {
        var p = raw2; p.clamp()
        guard !p.isIdentity else { return [] }
        let j = joints(raw)
        var out: [BrushStroke] = []
        let ls = j["left_shoulder_1_joint"], rs = j["right_shoulder_1_joint"], lh = j["left_hip_1_joint"], rh = j["right_hip_1_joint"]
        let lk = j["left_knee_1_joint"], rk = j["right_knee_1_joint"], la = j["left_ankle_1_joint"], ra = j["right_ankle_1_joint"]
        let le = j["left_elbow_1_joint"], re = j["right_elbow_1_joint"], neck = j["neck_1_joint"]
        // which way is "toward the middle" is decided by where each limb sits in the picture, not by Vision's left/right naming
        let midX = [ls, rs, lh, rh].compactMap { $0?.x }.reduce(0, +) / CGFloat(max([ls, rs, lh, rh].compactMap { $0 }.count, 1))
        func inward(_ pt: CGPoint) -> Double { pt.x < midX ? 1 : -1 }

        // Torso edges at a height: from the mask when there is one, else the joints widened to the body outline.
        func edges(y: Double, joint l: CGPoint, _ r: CGPoint, grow: Double) -> (CGPoint, CGPoint) {
            if let e = silhouette?(y), e.1 - e.0 > 0.02 { return (CGPoint(x: e.0, y: y), CGPoint(x: e.1, y: y)) }
            let mx = (l.x + r.x) / 2, half = abs(l.x - r.x) / 2 * grow
            return (CGPoint(x: mx - half, y: y), CGPoint(x: mx + half, y: y))
        }
        // Waist: 60% of the way from shoulders to hips; squeeze the torso edges.
        if p.waist != 0, let ls, let rs, let lh, let rh {
            let w = lerp(mid(ls, rs)!, mid(lh, rh)!, 0.6)
            let (l, r) = edges(y: Double(w.y), joint: lerp(ls, lh, 0.6), lerp(rs, rh, 0.6), grow: 1.5)
            squeeze(l, r, amount: p.waist, radius: Float(dist(ls, lh)) * 0.5, out: &out, reach: 0.12)
        }
        // Hips: squeeze (positive slims) at the hip outline.
        if p.hips != 0, let lh, let rh {
            let (l, r) = edges(y: Double(mid(lh, rh)!.y) + Double(dist(lh, rh)) * 0.2, joint: lh, rh, grow: 1.9)
            squeeze(l, r, amount: p.hips, radius: Float(abs(rh.x - lh.x)) * 1.1, out: &out, reach: 0.12)
        }
        // Shoulders: positive widens, so push outward (negative squeeze).
        if p.shoulder != 0, let ls, let rs {
            squeeze(ls, rs, amount: -p.shoulder, radius: Float(abs(rs.x - ls.x)) * 0.6, out: &out)
        }
        // Legs: slim squeezes each leg toward its own axis (hip-ankle line); length stretches the thigh region downward.
        if p.legSlim != 0 {
            for (hip, knee, ankle) in [(lh, lk, la), (rh, rk, ra)] {
                guard let hip, let knee, let ankle else { continue }
                let side = inward(hip)
                let thigh = lerp(hip, knee, 0.5), shin = lerp(knee, ankle, 0.5)
                let legW = Float(dist(hip, knee)) * 0.35
                for c in [thigh, shin] {
                    // push the outer side in; the inner side is handled by the other leg's stroke
                    out.append(BrushStroke(kind: .push, x: Float(c.x - side * Double(legW) * 0.5), y: Float(c.y), radius: legW * 1.4, strength: 1, dirX: Float(side * p.legSlim) * legW * 0.4, dirY: 0))
                }
            }
        }
        if p.legLength != 0, let lh, let rh, let lk, let rk, let la, let ra {
            let hipMid = mid(lh, rh)!, ankleMid = mid(la, ra)!, kneeMid = mid(lk, rk)!
            let span = Float(dist(hipMid, ankleMid))
            out.append(BrushStroke(kind: .push, x: Float(kneeMid.x), y: Float(kneeMid.y), radius: span * 0.55, strength: 1, dirX: 0, dirY: Float(p.legLength) * span * 0.12))
        }
        // Thighs and calves: squeeze (positive slims) at their midpoints, separately from the whole-leg slider.
        func slimSegment(_ top: CGPoint?, _ bottom: CGPoint?, side: Double, amount: Double) {
            guard let top, let bottom else { return }
            let c = lerp(top, bottom, 0.5), w = Float(dist(top, bottom)) * 0.3
            out.append(BrushStroke(kind: .push, x: Float(c.x - side * Double(w) * 0.5), y: Float(c.y), radius: w * 1.4, strength: 1, dirX: Float(side * amount) * w * 0.4, dirY: 0))
        }
        if p.thighs != 0 { slimSegment(lh, lk, side: lh.map(inward) ?? 1, amount: p.thighs); slimSegment(rh, rk, side: rh.map(inward) ?? -1, amount: p.thighs) }
        if p.calves != 0 { slimSegment(lk, la, side: lk.map(inward) ?? 1, amount: p.calves); slimSegment(rk, ra, side: rk.map(inward) ?? -1, amount: p.calves) }
        // Straighten: nudge each knee toward the line between its hip and ankle.
        if p.legStraighten != 0 {
            for (hip, knee, ankle) in [(lh, lk, la), (rh, rk, ra)] {
                guard let hip, let knee, let ankle else { continue }
                let target = lerp(hip, ankle, 0.5), dx = Float(target.x - knee.x)
                out.append(BrushStroke(kind: .push, x: Float(knee.x), y: Float(knee.y), radius: Float(dist(hip, ankle)) * 0.35, strength: 1, dirX: dx * Float(p.legStraighten), dirY: 0))
            }
        }
        // Arms: squeeze each arm at the elbow toward the torso side.
        if p.armSlim != 0 {
            for (shoulder, elbow) in [(ls, le), (rs, re)] {
                guard let shoulder, let elbow else { continue }
                let side = -inward(shoulder)
                let c = lerp(shoulder, elbow, 0.5), w = Float(dist(shoulder, elbow)) * 0.3
                out.append(BrushStroke(kind: .push, x: Float(c.x + side * Double(w) * 0.5), y: Float(c.y), radius: w * 1.6, strength: 1, dirX: Float(-side * p.armSlim) * w * 0.4, dirY: 0))
            }
        }
        // Head: pinch (smaller) or bloat (bigger) just above the neck.
        if p.headSize != 0, let neck, let ls, let rs {
            let r = Float(abs(rs.x - ls.x)) * 0.55
            out.append(BrushStroke(kind: p.headSize > 0 ? .bloat : .pinch, x: Float(neck.x), y: Float(neck.y) - r * 0.9, radius: r, strength: Float(abs(p.headSize)) * 0.45))
        }
        return out
    }

    static func strokes(poses: [[String: CGPoint]], params: BodyReshapeParams, silhouette: ((Double) -> (Double, Double)?)? = nil) -> [BrushStroke] {
        poses.flatMap { strokes(pose: $0, params: params, silhouette: silhouette) }
    }
}
