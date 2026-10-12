import CoreImage

/// "Copy colours from a photo": the reference's colour statistics (Lab mean and spread), applied to whatever the picture is at this step.
struct ColorMatch: Codable, Equatable {
    var mean: [Double] = []
    var std: [Double] = []
    var strength = 0.7
    var name = ""

    var isIdentity: Bool { strength <= 0 || mean.count != 3 || std.count != 3 }

    /// Statistics of a reference picture, sampled on a small copy.
    static func from(reference: CIImage, name: String = "") -> ColorMatch? {
        guard let s = sampleStats(reference) else { return nil }
        return ColorMatch(mean: s.mean, std: s.std, strength: 0.7, name: name)
    }

    static func sampleStats(_ image: CIImage, side: Int = 64) -> ColorTransfer.Stats? {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return nil }
        let small = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(side) / e.width, y: CGFloat(side) / e.height))
        var px = [UInt8](repeating: 0, count: side * side * 4)
        CIContext().render(small, toBitmap: &px, rowBytes: side * 4, bounds: CGRect(x: 0, y: 0, width: side, height: side), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var rgb: [Float] = []; rgb.reserveCapacity(side * side * 3)
        for i in 0..<(side * side) { rgb += [Float(px[i * 4]) / 255, Float(px[i * 4 + 1]) / 255, Float(px[i * 4 + 2]) / 255] }
        return ColorTransfer.stats(ofRGB: rgb)
    }

    func apply(to image: CIImage) -> CIImage {
        guard !isIdentity, let target = Self.sampleStats(image) else { return image }
        let lut = ColorTransfer.lut(target: target, reference: ColorTransfer.Stats(mean: mean, std: std), strength: strength)
        return lut.apply(to: image, intensity: 1)
    }
}
