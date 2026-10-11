import CoreGraphics
import CoreImage
import Foundation

/// HSL mixer, per-channel curves, split toning and posterize, all baked into one 3D LUT so they render through the same path as filters.
struct ColorGrade: Codable, Equatable {
    struct Band: Codable, Equatable { var hue = 0.0, sat = 0.0, lum = 0.0 }       // each -1...1
    struct Tone: Codable, Equatable { var hue = 0.0; var sat = 0.0 }               // hue 0...360, sat 0...1
    static let bandNames = ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"]
    static let bandCenters: [Double] = [0, 30, 60, 120, 180, 240, 280, 320]

    var bands = Array(repeating: Band(), count: 8)
    var rgbCurve = ToneCurve()
    var redCurve = ToneCurve()
    var greenCurve = ToneCurve()
    var blueCurve = ToneCurve()
    var shadows = Tone()
    var highlights = Tone()
    var balance = 0.0                 // -1 (more shadow tint) ... 1 (more highlight tint)
    var posterize = 0                 // 0 = off, else 2...16 levels per channel

    var isIdentity: Bool { self == ColorGrade() }

    // MARK: colour math
    static func hsl(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        guard d > 1e-9 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        return (h * 60, s, l)
    }

    static func rgb(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s > 1e-9 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func f(_ t0: Double) -> Double {
            var t = t0.truncatingRemainder(dividingBy: 1); if t < 0 { t += 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        return (f(hh + 1.0 / 3), f(hh), f(hh - 1.0 / 3))
    }

    /// Triangular weight of a hue for a band; neighbouring bands overlap so there are no seams.
    static func weight(hue: Double, band: Int) -> Double {
        let c = bandCenters[band]
        var d = abs(hue - c).truncatingRemainder(dividingBy: 360); if d > 180 { d = 360 - d }
        let width = band == 3 || band == 4 || band == 5 ? 60.0 : 45.0
        return max(0, 1 - d / width)
    }

    /// Applies the whole grade to one color (components 0...1).
    func apply(_ r0: Double, _ g0: Double, _ b0: Double) -> (Double, Double, Double) {
        var (r, g, b) = (min(max(r0, 0), 1), min(max(g0, 0), 1), min(max(b0, 0), 1))
        // curves: master first, then each channel
        r = redCurve.value(at: rgbCurve.value(at: r)); g = greenCurve.value(at: rgbCurve.value(at: g)); b = blueCurve.value(at: rgbCurve.value(at: b))
        // HSL mixer
        if bands.contains(where: { $0 != Band() }) {
            var (h, s, l) = Self.hsl(r, g, b)
            if s > 0.02 {
                var dh = 0.0, ds = 0.0, dl = 0.0
                for i in 0..<8 { let w = Self.weight(hue: h, band: i) * min(s * 2, 1); dh += w * bands[i].hue * 30; ds += w * bands[i].sat; dl += w * bands[i].lum * 0.25 }
                h += dh; s = min(max(s * (1 + ds), 0), 1); l = min(max(l + dl, 0), 1)
                (r, g, b) = Self.rgb(h, s, l)
            }
        }
        // split toning: tint dark areas and bright areas
        if shadows.sat > 0 || highlights.sat > 0 {
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let sw = (1 - y) * (1 - y) * (balance <= 0 ? 1 : 1 - balance), hw = y * y * (balance >= 0 ? 1 : 1 + balance)
            for (tone, w) in [(shadows, sw), (highlights, hw)] where tone.sat > 0 {
                let t = Self.rgb(tone.hue, 1, 0.5), a = tone.sat * w * 0.5
                r += (t.0 - r) * a; g += (t.1 - g) * a; b += (t.2 - b) * a
            }
        }
        if posterize >= 2 {
            let n = Double(min(posterize, 16) - 1)
            r = (r * n).rounded() / n; g = (g * n).rounded() / n; b = (b * n).rounded() / n
        }
        return (min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1))
    }

    func lut(size: Int = 17) -> LUT {
        var v: [Float] = []; v.reserveCapacity(size * size * size * 3)
        let d = Double(size - 1)
        for bi in 0..<size { for gi in 0..<size { for ri in 0..<size {
            let o = apply(Double(ri) / d, Double(gi) / d, Double(bi) / d)
            v += [Float(o.0), Float(o.1), Float(o.2)]
        } } }
        return LUT(size: size, rgb: v)
    }

    // MARK: curve presets by channel
    static let curvePresets: [String: (rgb: ToneCurve, r: ToneCurve, g: ToneCurve, b: ToneCurve)] = [
        "contrast": (ToneCurve.presets["contrast"]!, ToneCurve(), ToneCurve(), ToneCurve()),
        "fade": (ToneCurve.presets["fade"]!, ToneCurve(), ToneCurve(), ToneCurve()),
        "warm": (ToneCurve(), ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.56), CGPoint(x: 1, y: 1)]), ToneCurve(), ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 1, y: 1)])),
        "cool": (ToneCurve(), ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.45), CGPoint(x: 1, y: 1)]), ToneCurve(), ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.56), CGPoint(x: 1, y: 1)])),
    ]

    /// A simple 3-slider curve (shadows, midtones, highlights; each -1...1) for the UI.
    static func curve(shadows: Double, mids: Double, highlights: Double) -> ToneCurve {
        func c(_ v: Double) -> Double { min(max(v, 0), 1) }
        var ys = [0, c(0.25 + shadows * 0.15), c(0.5 + mids * 0.2), c(0.75 + highlights * 0.15), 1]
        for i in 1..<ys.count { ys[i] = max(ys[i], ys[i - 1]) }          // sliders never invert tones
        return ToneCurve(points: zip([0.0, 0.25, 0.5, 0.75, 1.0], ys).map { CGPoint(x: $0, y: $1) })
    }
}

/// Picking colors out of a photo (eyedropper) and summarizing its palette.
enum ColorSampler {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Color at a point in image pixels (bottom-left origin), averaged over a small square.
    static func sample(_ image: CIImage, at p: CGPoint, radius: CGFloat = 2) -> RGBA? {
        let e = image.extent
        guard e.contains(p) else { return nil }
        let r = CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2 + 1, height: radius * 2 + 1).intersection(e)
        guard !r.isEmpty else { return nil }
        let avg = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: r)])
        var px = [UInt8](repeating: 0, count: 4)
        context.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return RGBA(r: Double(px[0]) / 255, g: Double(px[1]) / 255, b: Double(px[2]) / 255, a: Double(px[3]) / 255)
    }

    /// Most common colors (coarsely bucketed), most frequent first.
    static func palette(_ image: CIImage, count: Int = 5) -> [RGBA] {
        let e = image.extent
        guard e.width > 0, e.height > 0, count > 0 else { return [] }
        let n = 48
        let small = image.transformed(by: CGAffineTransform(scaleX: CGFloat(n) / e.width, y: CGFloat(n) / e.height).translatedBy(x: -e.minX, y: -e.minY))
        var px = [UInt8](repeating: 0, count: n * n * 4)
        context.render(small, toBitmap: &px, rowBytes: n * 4, bounds: CGRect(x: 0, y: 0, width: n, height: n), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var buckets: [Int: (n: Int, r: Int, g: Int, b: Int)] = [:]
        for i in 0..<(n * n) where px[i * 4 + 3] > 128 {
            let key = Int(px[i * 4] >> 5) << 6 | Int(px[i * 4 + 1] >> 5) << 3 | Int(px[i * 4 + 2] >> 5)      // 3 bits per channel
            var b = buckets[key] ?? (0, 0, 0, 0); b.n += 1; b.r += Int(px[i * 4]); b.g += Int(px[i * 4 + 1]); b.b += Int(px[i * 4 + 2]); buckets[key] = b
        }
        return buckets.values.sorted { $0.n > $1.n }.prefix(count).map { RGBA(r: Double($0.r) / Double($0.n) / 255, g: Double($0.g) / Double($0.n) / 255, b: Double($0.b) / Double($0.n) / 255, a: 1) }
    }
}
