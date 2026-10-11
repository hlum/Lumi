import CoreImage
import CoreImage.CIFilterBuiltins

/// Warps the person but keeps the background where it was; fills the strip the person leaves behind.
enum ProtectedWarp {
    static func apply(_ field: DisplacementField, to image: CIImage, personMask: CIImage, inpainter: Inpainting?) throws -> CIImage {
        guard !field.isIdentity else { return image }
        let e = image.extent
        let warped = MeshWarpRenderer.apply(field, to: image)
        let warpedMask = MeshWarpRenderer.apply(field, to: personMask)

        // person from the warped picture, background from the original
        let blend = CIFilter.blendWithMask()
        blend.inputImage = warped; blend.backgroundImage = image; blend.maskImage = warpedMask
        let base = blend.outputImage?.cropped(to: e) ?? warped

        // the strip = was person, no longer is (original mask minus warped mask)
        let sub = CIFilter.subtractBlendMode()
        // subtractBlendMode computes background - input; we want personMask - warpedMask
        sub.inputImage = warpedMask; sub.backgroundImage = personMask
        guard let diff = sub.outputImage?.cropped(to: e) else { return base }
        let strip = diff.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 6, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 6, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 6, w: 0)]).applyingFilter("CIColorClamp")
        guard let inpainter, hasContent(strip) else { return base }
        return try inpainter.inpaint(base, mask: strip)
    }

    /// Cheap check on a downsampled copy: is any pixel above a threshold?
    static func hasContent(_ mask: CIImage) -> Bool {
        let e = mask.extent
        guard e.width > 0, e.height > 0 else { return false }
        let avg = mask.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: e)])
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return px[0] > 20
    }
}
