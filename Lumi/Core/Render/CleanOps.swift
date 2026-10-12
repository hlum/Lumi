import CoreImage
import CoreImage.CIFilterBuiltins

/// Clone-stamp repair and noise reduction. The clone source is the brushed area shifted back by `offset` (fraction of the long side).
struct CleanConfig: Codable, Equatable {
    var cloneMask: MaskCanvas?
    var offsetX = 0.1
    var offsetY = 0.0
    var denoise = 0.0               // 0...1

    var isIdentity: Bool { (cloneMask?.isEmpty ?? true) && denoise <= 0 }

    init(cloneMask: MaskCanvas? = nil, offsetX: Double = 0.1, offsetY: Double = 0, denoise: Double = 0) {
        self.cloneMask = cloneMask; self.offsetX = offsetX; self.offsetY = offsetY; self.denoise = denoise
    }
}

enum CleanOps {
    static func apply(_ c: CleanConfig, to image: CIImage) -> CIImage {
        var img = image
        let e = image.extent
        if let m = c.cloneMask, !m.isEmpty {
            let long = max(e.width, e.height)
            // the source sits at (x - offsetX, y - offsetY) in picture (y-down) coordinates, so content moves by +offset
            let source = image.clampedToExtent().transformed(by: CGAffineTransform(translationX: c.offsetX * long, y: -c.offsetY * long)).cropped(to: e)
            let f = CIFilter.blendWithMask()
            f.inputImage = source; f.backgroundImage = img; f.maskImage = MaskScaling.scaled(m, to: e).applyingGaussianBlur(sigma: 1.5).cropped(to: e)
            img = f.outputImage?.cropped(to: e) ?? img
        }
        if c.denoise > 0 {
            let n = CIFilter.noiseReduction()
            n.inputImage = img; n.noiseLevel = Float(0.02 + 0.06 * c.denoise); n.sharpness = Float(0.4)
            img = n.outputImage?.cropped(to: e) ?? img
        }
        return img
    }
}

/// Guided removal brushes: a preset widens the painted mask before LaMa fills it.
enum SpecialtyBrush: String, CaseIterable, Codable {
    case glare, lensFlare, tattoo, moire, glassesGlare, clothingWrinkle

    /// Pixels the mask grows by, as a fraction of the long side, so the fill covers halos and edges.
    var grow: Double {
        switch self {
        case .glare: 0.012
        case .lensFlare: 0.02
        case .tattoo: 0.006
        case .moire: 0.01
        case .glassesGlare: 0.008
        case .clothingWrinkle: 0.005
        }
    }
    /// Preset strength 0...1 for the blend of the fill over the original.
    var strength: Double {
        switch self {
        case .glare, .lensFlare, .tattoo: 1
        case .moire: 0.85
        case .glassesGlare: 0.9
        case .clothingWrinkle: 0.7
        }
    }
    var title: String {
        switch self {
        case .glare: "Glare"
        case .lensFlare: "Lens flare"
        case .tattoo: "Tattoo"
        case .moire: "Moiré"
        case .glassesGlare: "Glasses glare"
        case .clothingWrinkle: "Clothing wrinkles"
        }
    }
}
