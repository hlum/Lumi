import CoreImage

/// One-tap "fix the colour": looks at the picture's tones and colour cast and returns Adjust values that move it toward a normal exposure,
/// full tonal range and neutral colour. Conservative on purpose: it never pushes a slider past a gentle amount.
enum AutoFix {
    struct Measure: Equatable {
        var medianLuma: Double     // 0...1, as it looks (sRGB-encoded)
        var p2: Double, p98: Double
        var meanR: Double, meanG: Double, meanB: Double
        var chroma: Double         // mean distance of each pixel from grey
    }

    /// Statistics from RGB bytes (sRGB, 3 or 4 channels per pixel).
    static func measure(rgb: [UInt8], channels: Int = 4) -> Measure? {
        let n = rgb.count / channels
        guard n > 0, channels >= 3 else { return nil }
        var hist = [Int](repeating: 0, count: 256)
        var sr = 0.0, sg = 0.0, sb = 0.0, sc = 0.0
        for i in 0..<n {
            let r = Double(rgb[i * channels]), g = Double(rgb[i * channels + 1]), b = Double(rgb[i * channels + 2])
            hist[Int((0.2126 * r + 0.7152 * g + 0.0722 * b).rounded())] += 1
            sr += r; sg += g; sb += b
            let m = (r + g + b) / 3
            sc += (abs(r - m) + abs(g - m) + abs(b - m)) / 3
        }
        func percentile(_ p: Double) -> Double {
            var acc = 0, target = Int(Double(n) * p)
            for v in 0..<256 { acc += hist[v]; if acc > target { return Double(v) / 255 } }
            return 1
        }
        return Measure(medianLuma: percentile(0.5), p2: percentile(0.02), p98: percentile(0.98), meanR: sr / Double(n) / 255, meanG: sg / Double(n) / 255, meanB: sb / Double(n) / 255, chroma: sc / Double(n) / 255)
    }

    static func params(for m: Measure) -> AdjustParams {
        var p = AdjustParams()
        func clamp(_ v: Double, _ lim: Double) -> Double { min(max(v, -lim), lim) }
        // exposure: bring the median toward 0.47 as it looks; a stop of EV is 0.5 on the slider
        let lin = { (v: Double) in pow(max(v, 0.01), 2.2) }
        let ev = log2(lin(0.47) / lin(max(m.medianLuma, 0.02)))
        p.exposure = clamp(ev / 2 * 0.7, 0.5)
        // range: if the bright end stops short, lift whites; if the dark end is lifted, deepen blacks
        if m.p98 < 0.95 { p.whites = clamp((0.95 - m.p98) * 1.6, 0.5) }
        if m.p2 > 0.06 { p.blacks = -clamp((m.p2 - 0.06) * 1.8, 0.5) }
        if m.p98 - m.p2 < 0.6 { p.contrast = clamp((0.6 - (m.p98 - m.p2)) * 0.8, 0.35) }
        // colour cast: gray world, split into warm/cool and green/magenta
        let avg = (m.meanR + m.meanG + m.meanB) / 3
        if avg > 0.03 {
            p.temperature = clamp(((m.meanB - m.meanR) / avg) * 0.6, 0.35)          // too blue -> warm it up
            p.tint = clamp(((m.meanG - (m.meanR + m.meanB) / 2) / avg) * 0.6, 0.25)  // too green -> positive pushes toward magenta
        }
        if m.chroma < 0.08 { p.vibrance = clamp((0.08 - m.chroma) * 3, 0.3) }
        return p
    }

    static func params(for image: CIImage) -> AdjustParams {
        let e = image.extent, side = 96
        guard e.width > 0, e.height > 0 else { return AdjustParams() }
        let small = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(side) / e.width, y: CGFloat(side) / e.height))
        var px = [UInt8](repeating: 0, count: side * side * 4)
        CIContext().render(small, toBitmap: &px, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return measure(rgb: px).map(params(for:)) ?? AdjustParams()
    }
}
