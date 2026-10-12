import CoreImage
import CoreImage.CIFilterBuiltins

/// Classic effects, each driven by one 0...1 strength.
enum PhotoEffect: String, CaseIterable, Codable {
    case glitch, lightLeak, particles, zoomBlur, softGlow

    static func apply(_ e: PhotoEffect, strength: Double, to image: CIImage, seed: UInt64 = 7) -> CIImage {
        let s = min(max(strength, 0), 1)
        guard s > 0 else { return image }
        let ext = image.extent
        switch e {
        case .glitch:
            // red and blue pulled apart, plus a few horizontal strips thrown sideways
            let d = s * ext.width * 0.02
            func channel(_ c: [CGFloat], dx: CGFloat) -> CIImage {
                image.clampedToExtent().transformed(by: CGAffineTransform(translationX: dx, y: 0))
                    .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: c[0], y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: c[1], z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: c[2], w: 0)]).cropped(to: ext)
            }
            let split = channel([0, 0, 1], dx: -d).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: channel([0, 1, 0], dx: 0).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: channel([1, 0, 0], dx: d)])]).cropped(to: ext)
            var out = split
            var rng = SplitMix(seed: seed)
            for _ in 0..<Int(2 + s * 5) {
                let h = ext.height * (0.02 + 0.05 * rng.unit()), y = ext.minY + ext.height * rng.unit() * 0.9
                let strip = CGRect(x: ext.minX, y: y, width: ext.width, height: h)
                let shifted = split.clampedToExtent().transformed(by: CGAffineTransform(translationX: (rng.unit() - 0.5) * ext.width * 0.15 * s, y: 0)).cropped(to: strip)
                out = shifted.composited(over: out)
            }
            return out.cropped(to: ext)
        case .lightLeak:
            let g = CIFilter.radialGradient()
            g.center = CGPoint(x: ext.minX + ext.width * 0.05, y: ext.minY + ext.height * 0.9)
            g.radius0 = 0; g.radius1 = Float(max(ext.width, ext.height) * 0.7)
            g.color0 = CIColor(red: 1, green: 0.55, blue: 0.2, alpha: CGFloat(0.9 * s)); g.color1 = CIColor(red: 1, green: 0.3, blue: 0.4, alpha: 0)
            return (g.outputImage ?? CIImage()).applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: ext)
        case .particles:
            var rng = SplitMix(seed: seed)
            var layer = CIImage(color: .clear).cropped(to: ext)
            let g = CIFilter.radialGradient(); g.radius0 = 0
            for _ in 0..<Int(15 + s * 60) {
                let r = Float(2 + rng.unit() * ext.width * 0.01 * (1 + s * 2))
                g.center = CGPoint(x: ext.minX + ext.width * rng.unit(), y: ext.minY + ext.height * rng.unit()); g.radius1 = r
                g.color0 = CIColor(red: 1, green: 1, blue: 0.9, alpha: CGFloat(0.4 + 0.5 * rng.unit())); g.color1 = CIColor(red: 1, green: 1, blue: 0.9, alpha: 0)
                if let dot = g.outputImage { layer = dot.cropped(to: ext).composited(over: layer) }
            }
            return layer.composited(over: image).cropped(to: ext)
        case .zoomBlur:
            let f = CIFilter.zoomBlur(); f.inputImage = image.clampedToExtent(); f.center = CGPoint(x: ext.midX, y: ext.midY); f.amount = Float(s * 30)
            return f.outputImage?.cropped(to: ext) ?? image
        case .softGlow:
            let f = CIFilter.bloom(); f.inputImage = image; f.radius = Float(ext.width * 0.02 * (0.5 + s)); f.intensity = Float(s)
            return f.outputImage?.cropped(to: ext) ?? image
        }
    }
}

/// Tiny deterministic generator so an effect looks the same every render.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
