import CoreImage

enum OutlineOps {
    /// Adds a colored outline that follows the image's alpha edge. `width` is a fraction of the long side.
    static func apply(to image: CIImage, width: Double, color: CIColor = .white) -> CIImage {
        let e = image.extent
        let radius = max(1, width * Double(max(e.width, e.height)))
        let pad = ceil(radius) + 2
        let canvas = e.insetBy(dx: -pad, dy: -pad)
        let grown = image.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius]).cropped(to: canvas)
        // only the alpha of the dilated image matters: paint it solid, then put the original on top
        let solid = CIImage(color: color).cropped(to: canvas)
        let mask = grown.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        let outline = solid.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: canvas), kCIInputMaskImageKey: mask])
        return image.composited(over: outline).cropped(to: canvas)
    }
}
