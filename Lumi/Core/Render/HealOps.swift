import CoreImage
import CoreImage.CIFilterBuiltins

enum HealOps {
    /// Replaces each spot with the surrounding skin tone (a wide blur of its neighborhood), feathered at the edge.
    static func apply(_ spots: [SpotDetector.Spot], to image: CIImage) -> CIImage {
        guard !spots.isEmpty else { return image }
        let e = image.extent
        var mask = CIImage(color: .black).cropped(to: e)
        for s in spots {
            let g = CIFilter.radialGradient()
            g.center = CGPoint(x: e.minX + s.center.x, y: e.maxY - s.center.y)            // spots are y-down pixels
            g.radius0 = Float(s.radius); g.radius1 = Float(s.radius * 1.6); g.color0 = .white; g.color1 = .black
            if let dot = g.outputImage?.cropped(to: e) {
                mask = dot.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: e)
            }
        }
        let r = (spots.map(\.radius).max() ?? 4) * 3
        let fill = image.clampedToExtent().applyingFilter("CIMedianFilter").applyingGaussianBlur(sigma: r).cropped(to: e)
        let blend = CIFilter.blendWithMask(); blend.inputImage = fill; blend.backgroundImage = image; blend.maskImage = mask
        return blend.outputImage?.cropped(to: e) ?? image
    }
}
