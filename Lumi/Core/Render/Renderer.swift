import CoreImage
import CoreImage.CIFilterBuiltins

/// Pure function of its inputs: same image + parameters give the same output.
enum Renderer {
    static func render(_ frame: CIImage, exposure: Double) -> CIImage {
        guard exposure != 0 else { return frame }
        let f = CIFilter.exposureAdjust()
        f.inputImage = frame
        f.ev = Float(exposure)
        return f.outputImage ?? frame
    }

    static func render(_ frame: CIImage, document: EditDocument) -> CIImage {
        document.operations.reduce(frame) { img, op in
            switch op {
            case .exposure(let v): render(img, exposure: v)
            case .crop(let c): GeometryOps.apply(c, to: img)
            case .adjust(let a): AdjustOps.apply(a, to: img)
            case .curve(let c): AdjustOps.apply(c, to: img)
            case .warp(let w): MeshWarpRenderer.apply(w.field, to: img)
            case .layers(let l): LayerRenderer.render(l, over: img)
            }
        }
    }

    /// Downscale so the longest side is at most `maxDimension`; never upscales.
    static func proxy(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let s = maxDimension / longest
        return image.transformed(by: CGAffineTransform(scaleX: s, y: s))
    }
}
