import CoreImage
import CoreImage.CIFilterBuiltins

struct SkinParams: Codable, Equatable {
    var smooth = 0.0       // 0...1
    var texture = 0.5      // 0...1 how much fine detail is kept when smoothing
    var whiten = 0.0       // 0...1
    var rosy = 0.0         // 0...1
    var tan = 0.0          // 0...1
    var isIdentity: Bool { smooth == 0 && whiten == 0 && rosy == 0 && tan == 0 }
}

enum SkinOps {
    /// Applies skin retouching only where `mask` is white. Works on any image/mask pair of the same extent.
    static func apply(_ p: SkinParams, to image: CIImage, mask: CIImage) -> CIImage {
        guard !p.isIdentity else { return image }
        let e = image.extent
        var out = image

        if p.smooth > 0 {
            let s = min(max(p.smooth, 0), 1), keep = min(max(p.texture, 0), 1)
            let blur = CIFilter.gaussianBlur(); blur.inputImage = image.clampedToExtent(); blur.radius = Float(2 + 14 * s) * Float(min(e.width, e.height) / 1000 + 0.2)
            let blurred = (blur.outputImage ?? image).cropped(to: e)
            // add back a share of the detail (image - blurred) so skin stays real
            let detail = CIFilter.subtractBlendMode(); detail.inputImage = image; detail.backgroundImage = blurred
            let smoothed = blended(blurred, over: image, amount: s)
            out = keep > 0 ? addDetail(smoothed, detail: detail.outputImage, amount: keep * 0.5) : smoothed
        }
        if p.whiten > 0 {
            let f = CIFilter.colorControls(); f.inputImage = out
            f.brightness = Float(p.whiten * 0.12); f.saturation = Float(1 - p.whiten * 0.1)
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
            let f = CIFilter.colorControls(); f.inputImage = out
            f.brightness = Float(-p.tan * 0.08); f.saturation = Float(1 + p.tan * 0.1)
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

    private static func addDetail(_ base: CIImage, detail: CIImage?, amount: Double) -> CIImage {
        guard let detail else { return base }
        let scaled = detail.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0)])
        return scaled.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: base]).cropped(to: base.extent)
    }
}
