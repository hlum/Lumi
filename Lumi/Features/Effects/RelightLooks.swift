import CoreImage
import CoreImage.CIFilterBuiltins

/// Coloured relighting limited to the person: the light colours the subject, the background is left or darkened.
enum RelightLook: String, CaseIterable, Codable {
    case photoBooth, ledStrip, redLight, goldenHour

    func apply(to image: CIImage, personMask: CIImage?, strength: Double) -> CIImage {
        let s = CGFloat(min(max(strength, 0), 1))
        guard s > 0 else { return image }
        let e = image.extent
        let light: CIImage
        switch self {
        case .photoBooth:   // flat warm flash from the front
            light = CIImage(color: CIColor(red: 1, green: 0.93, blue: 0.82)).cropped(to: e)
        case .redLight:
            light = CIImage(color: CIColor(red: 1, green: 0.1, blue: 0.1)).cropped(to: e)
        case .goldenHour:
            light = CIImage(color: CIColor(red: 1, green: 0.7, blue: 0.35)).cropped(to: e)
        case .ledStrip:     // magenta from the left, cyan from the right
            let g = CIFilter.linearGradient()
            g.point0 = CGPoint(x: e.minX, y: e.midY); g.point1 = CGPoint(x: e.maxX, y: e.midY)
            g.color0 = CIColor(red: 1, green: 0.1, blue: 0.8); g.color1 = CIColor(red: 0.1, green: 0.8, blue: 1)
            light = (g.outputImage ?? CIImage()).cropped(to: e)
        }
        let mode = self == .photoBooth ? "CISoftLightBlendMode" : "CIOverlayBlendMode"
        var lit = light.applyingFilter(mode, parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
        // photo booth also darkens the surroundings a little
        if self == .photoBooth { lit = lit.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 0.8 * s, kCIInputRadiusKey: 2]).cropped(to: e) }
        let amount = s
        let mask: CIImage
        if let personMask {
            mask = personMask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0)])
        } else { mask = CIImage(color: CIColor(red: amount, green: amount, blue: amount)).cropped(to: e) }
        let f = CIFilter.blendWithMask(); f.inputImage = lit; f.backgroundImage = image; f.maskImage = mask
        return f.outputImage?.cropped(to: e) ?? image
    }
}
