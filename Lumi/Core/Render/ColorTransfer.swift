import Foundation

/// Reinhard-style color transfer in CIELAB: match the target's per-channel mean/std to a reference's.
/// The result is baked into a `LUT`, so it renders through the same path as any filter.
enum ColorTransfer {
    struct Stats: Equatable { var mean: [Double]; var std: [Double] }

    // sRGB <-> Lab (D65)
    static func lab(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (lr, lg, lb) = (lin(r), lin(g), lin(b))
        let x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / 0.95047
        let y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb
        let z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let (fx, fy, fz) = (f(x), f(y), f(z))
        return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
    }

    static func rgb(fromLab L: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
        let fy = (L + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        func inv(_ t: Double) -> Double { t * t * t > 216.0 / 24389 ? t * t * t : (116 * t - 16) / (24389.0 / 27) }
        let x = inv(fx) * 0.95047, y = inv(fy), z = inv(fz) * 1.08883
        let lr = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let lg = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let lb = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        func gamma(_ c: Double) -> Double {
            let v = min(max(c, 0), 1)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return (gamma(lr), gamma(lg), gamma(lb))
    }

    /// Stats over interleaved RGB (0...1) pixels.
    static func stats(ofRGB px: [Float]) -> Stats {
        let n = px.count / 3
        guard n > 0 else { return Stats(mean: [0, 0, 0], std: [0, 0, 0]) }
        var sum = [0.0, 0, 0], sq = [0.0, 0, 0]
        for i in 0..<n {
            let l = lab(Double(px[i * 3]), Double(px[i * 3 + 1]), Double(px[i * 3 + 2]))
            for c in 0..<3 { sum[c] += l[c]; sq[c] += l[c] * l[c] }
        }
        let mean = sum.map { $0 / Double(n) }
        let std = (0..<3).map { max(sq[$0] / Double(n) - mean[$0] * mean[$0], 0).squareRoot() }
        return Stats(mean: mean, std: std)
    }

    /// Builds a LUT that moves `target` statistics onto `reference`. `strength` blends toward identity.
    static func lut(target: Stats, reference: Stats, size: Int = 17, strength: Double = 1) -> LUT {
        let s = min(max(strength, 0), 1)
        var v: [Float] = []; v.reserveCapacity(size * size * size * 3)
        let d = Double(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let (R, G, B) = (Double(r) / d, Double(g) / d, Double(b) / d)
            var l = lab(R, G, B)
            for c in 0..<3 {
                let scale = target.std[c] < 1e-6 ? 1 : min(reference.std[c] / target.std[c], 4)
                l[c] = (l[c] - target.mean[c]) * scale + reference.mean[c]
            }
            let o = rgb(fromLab: l[0], l[1], l[2])
            v += [Float(R + (o.0 - R) * s), Float(G + (o.1 - G) * s), Float(B + (o.2 - B) * s)]
        } } }
        return LUT(size: size, rgb: v)
    }
}
