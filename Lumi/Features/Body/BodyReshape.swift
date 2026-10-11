import CoreGraphics
import Foundation

/// Slider values, each -1...1 (0 = off).
struct BodyReshapeParams: Codable, Equatable {
    var waist = 0.0, legLength = 0.0, legSlim = 0.0, armSlim = 0.0, shoulder = 0.0, headSize = 0.0, hips = 0.0

    var isIdentity: Bool { self == BodyReshapeParams() }
    mutating func clamp() {
        func c(_ v: inout Double) { v = min(max(v, -1), 1) }
        c(&waist); c(&legLength); c(&legSlim); c(&armSlim); c(&shoulder); c(&headSize); c(&hips)
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

    /// Pushes the two sides of a body part toward its center line.
    private static func squeeze(_ left: CGPoint, _ right: CGPoint, amount: Double, radius: Float, out: inout [BrushStroke], reach: Double = 0.06) {
        let width = Float(abs(right.x - left.x))
        out.append(BrushStroke(kind: .push, x: Float(left.x), y: Float(left.y), radius: radius, strength: 1, dirX: Float(amount) * width * Float(reach) * 4, dirY: 0))
        out.append(BrushStroke(kind: .push, x: Float(right.x), y: Float(right.y), radius: radius, strength: 1, dirX: -Float(amount) * width * Float(reach) * 4, dirY: 0))
    }

    static func strokes(pose raw: [String: CGPoint], params raw2: BodyReshapeParams) -> [BrushStroke] {
        var p = raw2; p.clamp()
        guard !p.isIdentity else { return [] }
        let j = joints(raw)
        var out: [BrushStroke] = []
        let ls = j["left_shoulder_1_joint"], rs = j["right_shoulder_1_joint"], lh = j["left_hip_1_joint"], rh = j["right_hip_1_joint"]
        let lk = j["left_knee_1_joint"], rk = j["right_knee_1_joint"], la = j["left_ankle_1_joint"], ra = j["right_ankle_1_joint"]
        let le = j["left_elbow_1_joint"], re = j["right_elbow_1_joint"], neck = j["neck_1_joint"]

        // Waist: between shoulders and hips, 60% of the way down; squeeze the torso edges.
        if p.waist != 0, let ls, let rs, let lh, let rh {
            let l = lerp(ls, lh, 0.6), r = lerp(rs, rh, 0.6)
            squeeze(l, r, amount: p.waist, radius: Float(dist(ls, lh)) * 0.6, out: &out)
        }
        // Hips: squeeze (positive slims) at hip joints.
        if p.hips != 0, let lh, let rh {
            squeeze(lh, rh, amount: p.hips, radius: Float(abs(rh.x - lh.x)) * 0.9, out: &out)
        }
        // Shoulders: positive widens, so push outward (negative squeeze).
        if p.shoulder != 0, let ls, let rs {
            squeeze(ls, rs, amount: -p.shoulder, radius: Float(abs(rs.x - ls.x)) * 0.6, out: &out)
        }
        // Legs: slim squeezes each leg toward its own axis (hip-ankle line); length stretches the thigh region downward.
        if p.legSlim != 0 {
            for (hip, knee, ankle, side) in [(lh, lk, la, 1.0), (rh, rk, ra, -1.0)] {
                guard let hip, let knee, let ankle else { continue }
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
        // Arms: squeeze each arm at the elbow toward the torso side.
        if p.armSlim != 0 {
            for (shoulder, elbow, side) in [(ls, le, -1.0), (rs, re, 1.0)] {
                guard let shoulder, let elbow else { continue }
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

    static func strokes(poses: [[String: CGPoint]], params: BodyReshapeParams) -> [BrushStroke] {
        poses.flatMap { strokes(pose: $0, params: params) }
    }
}
