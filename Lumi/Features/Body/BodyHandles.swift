import CoreGraphics
import CoreImage
import Foundation

/// The person mask as a small bitmap, so many rows can be scanned without a GPU round trip each.
struct SilhouetteRaster {
    let width: Int, height: Int
    private let px: [UInt8]

    init?(mask: CIImage, width: Int = 320) {
        let e = mask.extent
        guard e.width > 0, e.height > 0 else { return nil }
        let h = max(Int((Double(width) * e.height / e.width).rounded()), 2)
        let small = mask.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(width) / e.width, y: CGFloat(h) / e.height))
        var buf = [UInt8](repeating: 0, count: width * h)
        CIContext(options: [.workingColorSpace: NSNull()]).render(small, toBitmap: &buf, rowBytes: width, bounds: CGRect(x: 0, y: 0, width: width, height: h), format: .L8, colorSpace: nil)
        self.width = width; self.height = h; px = buf          // row 0 is the top of the picture
    }

    init(width: Int, height: Int, pixels: [UInt8]) { self.width = width; self.height = height; px = pixels }

    func inside(x: Double, y: Double) -> Bool {
        let i = Int(x * Double(width)), j = Int(y * Double(height))
        guard i >= 0, i < width, j >= 0, j < height else { return false }
        return px[j * width + i] > 127
    }

    /// Left and right edge (normalized x) of the run of person pixels on row `y` (y-down) that contains `x`.
    func run(y: Double, x: Double) -> (Double, Double)? {
        let j = Int(y * Double(height))
        guard j >= 0, j < height else { return nil }
        let row = Array(px[(j * width)..<((j + 1) * width)])
        return BodySilhouette.run(row, around: Int(min(max(x, 0), 1) * Double(width - 1)))
    }
}

/// Body sliders as edge moves for the rigid MLS warp: each part's real outline moves toward its bone,
/// and pins just outside the outline hold the background, so walls and door frames stay where they are.
enum BodyHandles {
    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
    private static func dist(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }
    private static func bump(_ t: Double) -> Double { let s = sin(.pi * min(max(t, 0), 1)); return s * s }   // 0 at both ends, 1 in the middle

    /// Handles for one person. `raster` is the person mask when known; without it the outline is estimated from the joints.
    static func handles(pose raw: [String: CGPoint], params raw2: BodyReshapeParams, aspect: Double, raster: SilhouetteRaster?) -> [WarpHandle] {
        var p = raw2; p.clamp()
        guard !p.isIdentity else { return [] }
        let j = BodyReshape.joints(raw)
        let ls = j["left_shoulder_1_joint"], rs = j["right_shoulder_1_joint"], lh = j["left_hip_1_joint"], rh = j["right_hip_1_joint"]
        let lk = j["left_knee_1_joint"], rk = j["right_knee_1_joint"], la = j["left_ankle_1_joint"], ra = j["right_ankle_1_joint"]
        let le = j["left_elbow_1_joint"], re = j["right_elbow_1_joint"], lw = j["left_wrist_1_joint"], rw = j["right_wrist_1_joint"], neck = j["neck_1_joint"]
        var out: [WarpHandle] = []

        /// Edges of the part around `centre` on row y: from the mask (clipped so a hanging arm isn't taken for the waist), or estimated.
        func edges(y: Double, centre: Double, halfGuess: Double, stopAt limbs: [Double] = [], reach: Double = 1.6) -> (Double, Double) {
            var l = centre - halfGuess, r = centre + halfGuess
            if let run = raster?.run(y: y, x: centre), run.1 - run.0 > halfGuess * 0.6 { l = run.0; r = run.1 }
            // a part touching another (an arm against the torso) makes one long run: never reach much past the expected width
            l = max(l, centre - halfGuess * reach); r = min(r, centre + halfGuess * reach)
            for x in limbs {      // an arm joint inside the run: the torso edge is inside the arm
                if x < centre, x > l { l = max(l, x + halfGuess * 0.15) }
                if x > centre, x < r { r = min(r, x - halfGuess * 0.15) }
            }
            return (l, r)
        }
        /// Moves the two edges of a part at row y toward `axis` by `frac` of the half width; pins just outside each edge.
        func squeeze(y: Double, axis: Double, l: Double, r: Double, frac: Double) {
            let half = (r - l) / 2, gap = max(half * 0.35, 0.012)
            out.append(WarpHandle(from: CGPoint(x: l, y: y), to: CGPoint(x: l + (axis - l) * frac, y: y)))
            out.append(WarpHandle(from: CGPoint(x: r, y: y), to: CGPoint(x: r + (axis - r) * frac, y: y)))
            out.append(.pin(CGPoint(x: l - gap, y: y))); out.append(.pin(CGPoint(x: r + gap, y: y)))
        }
        /// A part between two joints, sampled at several heights with a smooth profile.
        func part(_ a: CGPoint, _ b: CGPoint, amount: Double, strength: Double, halfGuess: Double, from t0: Double = 0, to t1: Double = 1, reach: Double = 1.6, limbs: (Double) -> [Double] = { _ in [] }) {
            guard amount != 0 else { return }
            for k in 0...8 {
                let u = Double(k) / 8, t = t0 + (t1 - t0) * u
                let c = lerp(a, b, t)
                let (l, r) = edges(y: Double(c.y), centre: Double(c.x), halfGuess: halfGuess, stopAt: limbs(Double(c.y)), reach: reach)
                let f = amount * strength * bump(u)
                if abs(f) < 1e-4 { out.append(.pin(CGPoint(x: l, y: Double(c.y)))); out.append(.pin(CGPoint(x: r, y: Double(c.y)))); continue }
                squeeze(y: Double(c.y), axis: Double(c.x), l: l, r: r, frac: f)
            }
        }
        func armX(_ y: Double) -> [Double] {   // where the arms are at height y
            var xs: [Double] = []
            for (s, e, w) in [(ls, le, lw), (rs, re, rw)] {
                guard let s, let e else { continue }
                for (a, b) in [(s, e), (e, w ?? e)] where (min(a.y, b.y)...max(a.y, b.y)).contains(CGFloat(y)) && a.y != b.y {
                    xs.append(Double(a.x + (b.x - a.x) * (CGFloat(y) - a.y) / (b.y - a.y)))
                }
            }
            return xs
        }

        if let ls, let rs, let lh, let rh {
            let sh = lerp(ls, rs, 0.5), hip = lerp(lh, rh, 0.5), torsoHalf = dist(ls, rs) * 0.45
            part(sh, hip, amount: p.waist, strength: 0.16, halfGuess: torsoHalf, from: 0.35, to: 1.05, reach: 2.5, limbs: armX)
            let hipHalf = max(dist(lh, rh), dist(ls, rs) * 0.5) * 0.9
            let below = CGPoint(x: hip.x, y: hip.y + CGFloat(dist(sh, hip)) * 0.45)
            part(lerp(sh, hip, 0.8), below, amount: p.hips, strength: 0.14, halfGuess: hipHalf, reach: 2.5, limbs: armX)
            // shoulders: the outer edge at shoulder height out or in, chest held
            if p.shoulder != 0 {
                let y = Double(sh.y) + dist(sh, hip) * 0.08
                let (l, r) = edges(y: y, centre: Double(sh.x), halfGuess: dist(ls, rs) * 0.6)
                squeeze(y: y, axis: Double(sh.x), l: l, r: r, frac: -0.1 * p.shoulder)
                out.append(.pin(CGPoint(x: Double(sh.x), y: Double(sh.y)))); out.append(.pin(hip))
            }
        }
        for (h, k, a) in [(lh, lk, la), (rh, rk, ra)] {
            guard let h, let k else { continue }
            let legHalf = dist(h, k) * 0.2
            part(h, k, amount: p.thighs + p.legSlim * 0.7, strength: 0.18, halfGuess: legHalf)
            if let a { part(k, a, amount: p.calves + p.legSlim * 0.7, strength: 0.18, halfGuess: legHalf * 0.75) }
            if let a, p.legStraighten != 0 {
                let target = lerp(h, a, 0.5)
                out.append(WarpHandle(from: k, to: CGPoint(x: k.x + (target.x - k.x) * CGFloat(0.8 * p.legStraighten), y: k.y)))
                out.append(.pin(h)); out.append(.pin(a))
            }
        }
        for (s, e, w) in [(ls, le, lw), (rs, re, rw)] {
            guard let s, let e else { continue }
            let armHalf = dist(s, e) * 0.16
            // only arms that hang roughly down can be measured on rows
            if abs(e.y - s.y) > abs(e.x - s.x) { part(s, e, amount: p.armSlim, strength: 0.2, halfGuess: armHalf) }
            if let w, abs(w.y - e.y) > abs(w.x - e.x) { part(e, w, amount: p.armSlim, strength: 0.2, halfGuess: armHalf * 0.8) }
        }
        // legs longer: everything below the hips stretches down, feet move most
        if p.legLength != 0, let lh, let rh {
            let hip = lerp(lh, rh, 0.5)
            var feet = [la, ra].compactMap { $0 }
            if feet.isEmpty { feet = [lk, rk].compactMap { $0 } }
            if let lowest = feet.map(\.y).max() {
                let span = Double(lowest - hip.y), dy = span * 0.12 * p.legLength
                out.append(.pin(CGPoint(x: Double(hip.x) - 0.2, y: Double(hip.y)))); out.append(.pin(hip)); out.append(.pin(CGPoint(x: Double(hip.x) + 0.2, y: Double(hip.y))))
                // whole rows move, so the floor and walls stretch evenly instead of kinking around the feet
                for i in 0...10 {
                    let x = Double(i) / 10
                    out.append(.pin(CGPoint(x: x, y: Double(hip.y))))
                    out.append(WarpHandle(from: CGPoint(x: x, y: Double(lowest)), to: CGPoint(x: x, y: Double(lowest) + dy)))
                    let kneeY = Double(hip.y) + Double(lowest - hip.y) * 0.5
                    out.append(WarpHandle(from: CGPoint(x: x, y: kneeY), to: CGPoint(x: x, y: kneeY + dy * 0.5)))
                }
                // below the feet everything slides down by the same amount and the lowest strip leaves the frame, so feet keep their shape
                if dy > 0, 1 - dy > Double(lowest) + 0.01 {
                    for i in 0...10 { let x = Double(i) / 10; out.append(WarpHandle(from: CGPoint(x: x, y: 1 - dy), to: CGPoint(x: x, y: 1))) }
                }
            }
        }
        // head: the head outline scaled about the neck
        if p.headSize != 0, let neck, let ls, let rs {
            let r = dist(ls, rs) * 0.38, ctr = CGPoint(x: neck.x, y: neck.y - CGFloat(r * 1.1)), k = 1 + 0.15 * p.headSize
            for i in 0..<12 {
                let t = Double(i) / 12 * 2 * .pi
                let pt = CGPoint(x: Double(ctr.x) + cos(t) * r / aspect, y: Double(ctr.y) + sin(t) * r)
                out.append(WarpHandle(from: pt, to: CGPoint(x: Double(ctr.x) + (Double(pt.x) - Double(ctr.x)) * k, y: Double(ctr.y) + (Double(pt.y) - Double(ctr.y)) * k)))
            }
            out.append(.pin(ls)); out.append(.pin(rs)); out.append(.pin(neck))
        }
        return out
    }
}
