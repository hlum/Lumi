import CoreImage
import CoreImage.CIFilterBuiltins

struct SkinParams: Codable, Equatable {
    var smooth = 0.0       // 0...1
    var texture = 0.5      // 0...1 how much fine detail is kept when smoothing
    var whiten = 0.0       // 0...1
    var rosy = 0.0         // 0...1
    var tan = 0.0          // 0...1
    var even = 0.0         // 0...1 even out blotchy colour (keeps light and shade)
    var matte = 0.0        // 0...1 tone down shine
    var glow = 0.0         // 0...1 soft, healthy glow
    var isIdentity: Bool { smooth == 0 && whiten == 0 && rosy == 0 && tan == 0 && even == 0 && matte == 0 && glow == 0 }
}

extension SkinParams {
    /// Old drafts have no even, matte or glow.
    init(from decoder: Decoder) throws {
        enum K: String, CodingKey { case smooth, texture, whiten, rosy, tan, even, matte, glow }
        let c = try decoder.container(keyedBy: K.self)
        self.init()
        func d(_ k: K, _ def: Double) throws -> Double { try c.decodeIfPresent(Double.self, forKey: k) ?? def }
        smooth = try d(.smooth, 0); texture = try d(.texture, 0.5); whiten = try d(.whiten, 0); rosy = try d(.rosy, 0); tan = try d(.tan, 0)
        even = try d(.even, 0); matte = try d(.matte, 0); glow = try d(.glow, 0)
    }
}

enum SkinOps {
    /// Applies skin retouching only where `mask` is white. Works on any image/mask pair of the same extent.
    static func apply(_ p: SkinParams, to image: CIImage, mask: CIImage) -> CIImage {
        guard !p.isIdentity else { return image }
        let e = image.extent
        var out = image

        if p.smooth > 0 {
            // blur in display (gamma) space and mix both ways, so light and dark pores level out without the skin getting brighter
            let s = min(max(p.smooth, 0), 1), keep = min(max(p.texture, 0), 1)
            let radius = Double(2 + 14 * s) * Double(min(e.width, e.height) / 1000 + 0.2)
            out = AdjustOps.gamma(image) { g in
                let blurred = g.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: e)
                return blended(blurred, over: g, amount: s * (1 - 0.5 * keep))
            }
        }
        if p.even > 0 {
            // take colour from a wide average and light from the photo: blotches level out, shading stays
            let wide = out.clampedToExtent().applyingGaussianBlur(sigma: Double(min(e.width, e.height)) * 0.02).cropped(to: e)
            let colored = wide.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: out]).cropped(to: e)
            out = blended(colored, over: out, amount: min(p.even, 1))
        }
        if p.matte > 0 {
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = out; f.highlightAmount = Float(1 - 0.75 * min(p.matte, 1)); f.shadowAmount = 0
            out = (f.outputImage ?? out).cropped(to: e)
        }
        if p.glow > 0 {
            let f = CIFilter.bloom(); f.inputImage = out; f.radius = Float(min(e.width, e.height) * 0.02); f.intensity = Float(min(p.glow, 1) * 0.55)
            out = (f.outputImage ?? out).cropped(to: e)
        }
        if p.whiten > 0 {
            // a midtone lift, so skin gets lighter without the black and white points moving (an added offset washes it out)
            let w = p.whiten
            out = AdjustOps.curved(out, ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.25 + 0.07 * w), CGPoint(x: 0.5, y: 0.5 + 0.12 * w), CGPoint(x: 0.75, y: 0.75 + 0.07 * w), CGPoint(x: 1, y: 1)]))
            let f = CIFilter.colorControls(); f.inputImage = out; f.saturation = Float(1 - w * 0.1)
            out = f.outputImage ?? out
        }
        if p.rosy > 0 {
            let f = CIFilter.colorMatrix(); f.inputImage = out
            let a = CGFloat(p.rosy * 0.08)
            f.rVector = CIVector(x: 1, y: 0, z: 0, w: 0); f.gVector = CIVector(x: 0, y: 1 - a, z: 0, w: 0); f.bVector = CIVector(x: 0, y: 0, z: 1 - a, w: 0)
            f.biasVector = CIVector(x: a * 0.6, y: 0, z: a * 0.1, w: 0)
            out = f.outputImage ?? out
        }
        if p.tan > 0 {
            let t = p.tan
            out = AdjustOps.curved(out, ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.25 - 0.05 * t), CGPoint(x: 0.5, y: 0.5 - 0.09 * t), CGPoint(x: 0.75, y: 0.75 - 0.05 * t), CGPoint(x: 1, y: 1)]))
            let f = CIFilter.colorControls(); f.inputImage = out; f.saturation = Float(1 + t * 0.1)
            out = f.outputImage ?? out
        }
        let m = CIFilter.blendWithMask()
        m.inputImage = out.cropped(to: e); m.backgroundImage = image; m.maskImage = mask
        return m.outputImage?.cropped(to: e) ?? image
    }

    private static func blended(_ top: CIImage, over bottom: CIImage, amount: Double) -> CIImage {
        let f = CIFilter.dissolveTransition(); f.inputImage = bottom; f.targetImage = top; f.time = Float(amount)
        return (f.outputImage ?? top).cropped(to: bottom.extent)
    }
}
