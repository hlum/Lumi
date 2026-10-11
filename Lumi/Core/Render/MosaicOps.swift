import CoreImage
import CoreImage.CIFilterBuiltins

enum MosaicOps {
    enum Style: String, Codable { case pixel, blur }

    /// Pixelates / blurs `image` only where `mask` (white) is set. `block` is the cell size in pixels.
    static func apply(_ style: Style, to image: CIImage, mask: CIImage, block: Double) -> CIImage {
        let e = image.extent
        let effect: CIImage
        switch style {
        case .pixel:
            let f = CIFilter.pixellate()
            f.inputImage = image; f.scale = Float(max(block, 1)); f.center = CGPoint(x: e.minX, y: e.minY)
            effect = f.outputImage ?? image
        case .blur:
            let f = CIFilter.gaussianBlur()
            f.inputImage = image.clampedToExtent(); f.radius = Float(max(block, 1))
            effect = f.outputImage ?? image
        }
        let m = CIFilter.blendWithMask()
        m.inputImage = effect.cropped(to: e); m.backgroundImage = image; m.maskImage = mask
        return m.outputImage?.cropped(to: e) ?? image
    }

    /// White rectangles on black, sized to `extent`. Rects are normalized with a bottom-left origin.
    static func mask(rects: [CGRect], extent: CGRect) -> CIImage {
        var m = CIImage(color: .black).cropped(to: extent)
        for r in rects {
            let px = CGRect(x: extent.minX + r.minX * extent.width, y: extent.minY + r.minY * extent.height,
                            width: r.width * extent.width, height: r.height * extent.height)
            m = CIImage(color: .white).cropped(to: px).composited(over: m)
        }
        return m.cropped(to: extent)
    }
}
