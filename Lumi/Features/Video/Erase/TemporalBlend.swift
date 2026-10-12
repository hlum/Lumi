import CoreImage

/// Cuts flicker in per-frame fills: inside the erased area each new frame is mixed with the previous result.
struct TemporalBlend {
    var weight = 0.5                  // share of the previous frame kept inside the mask, 0...0.9
    private var previous: CIImage?

    /// `filled`: this frame after inpainting; `mask`: white where it was erased.
    mutating func blend(filled: CIImage, mask: CIImage) -> CIImage {
        let e = filled.extent
        guard let p = previous, p.extent == e else { previous = filled; return filled }
        let w = CGFloat(min(max(weight, 0), 0.9))
        let mix = CIFilter(name: "CIDissolveTransition", parameters: [kCIInputImageKey: filled, kCIInputTargetImageKey: p, kCIInputTimeKey: w])!.outputImage?.cropped(to: e) ?? filled
        let f = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: mix, kCIInputBackgroundImageKey: filled, kCIInputMaskImageKey: mask])!
        let out = f.outputImage?.cropped(to: e) ?? filled
        previous = out
        return out
    }

    mutating func reset() { previous = nil }
}
