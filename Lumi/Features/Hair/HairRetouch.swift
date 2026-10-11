import CoreImage
import CoreImage.CIFilterBuiltins

/// Everything the Hair tab can change, as one document operation.
struct HairRetouch: Codable, Equatable {
    var dye = HairColorParams()
    var deOil = 0.0                 // 0...1 calm greasy highlights inside the hair
    var smooth = 0.0                // 0...1 soften frizz and flyaways
    var rootRetouch = 0.0           // 0...1 darken and blend the roots near the scalp
    var add: MaskCanvas?            // brushed-in hair
    var remove: MaskCanvas?         // brushed-out areas that are not hair
    var isIdentity: Bool { dye.isIdentity && deOil == 0 && smooth == 0 && rootRetouch == 0 }

    static let swatches: [(category: String, name: String, color: RGBA)] = [
        ("Natural", "Black", RGBA(r: 0.06, g: 0.05, b: 0.05, a: 1)), ("Natural", "Dark brown", RGBA(r: 0.2, g: 0.12, b: 0.08, a: 1)), ("Natural", "Chestnut", RGBA(r: 0.4, g: 0.22, b: 0.12, a: 1)),
        ("Natural", "Blonde", RGBA(r: 0.85, g: 0.7, b: 0.4, a: 1)), ("Natural", "Auburn", RGBA(r: 0.5, g: 0.2, b: 0.1, a: 1)),
        ("Fashion", "Rose gold", RGBA(r: 0.9, g: 0.6, b: 0.55, a: 1)), ("Fashion", "Silver", RGBA(r: 0.78, g: 0.8, b: 0.85, a: 1)), ("Fashion", "Milk tea", RGBA(r: 0.7, g: 0.55, b: 0.45, a: 1)),
        ("Vivid", "Pink", RGBA(r: 1, g: 0.4, b: 0.7, a: 1)), ("Vivid", "Blue", RGBA(r: 0.2, g: 0.45, b: 0.95, a: 1)), ("Vivid", "Purple", RGBA(r: 0.55, g: 0.3, b: 0.85, a: 1)), ("Vivid", "Green", RGBA(r: 0.2, g: 0.75, b: 0.45, a: 1)),
    ]
}

protocol HairMasking { func hairMasks(in image: CIImage) throws -> [CIImage] }

/// Uses face landmarks plus the foreground subject mask (see docs/spikes/hair.md for why there is no dedicated hair model).
struct EstimatedHairMasker: HairMasking {
    let faces: FaceLandmarking
    let subject: SubjectMasking
    func hairMasks(in image: CIImage) throws -> [CIImage] {
        guard let person = try subject.subjectMask(for: image) else { return [] }
        return try faces.faces(in: image).map { HairMask.estimate(person: person, face: $0) }
    }
}

enum HairRetouchRender {
    static func apply(_ h: HairRetouch, to image: CIImage, hairMasks: [CIImage]) -> CIImage {
        guard !h.isIdentity else { return image }
        let e = image.extent
        // one mask for all faces, plus brush edits
        var mask = hairMasks.reduce(CIImage(color: .black).cropped(to: e)) { $1.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]).cropped(to: e) }
        mask = HairMask.refine(mask, add: h.add, remove: h.remove)
        var out = image
        if h.dye.strength > 0 { out = HairOps.recolor(h.dye, image: out, mask: mask) }
        if h.deOil > 0 {
            // pull bright specular peaks down toward the local average
            let blurred = out.clampedToExtent().applyingGaussianBlur(sigma: Double(min(e.width, e.height)) * 0.01).cropped(to: e)
            let calmed = blurred.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.03 * h.deOil, kCIInputContrastKey: 1 - 0.1 * h.deOil])
            out = blend(calmed, over: out, mask: mask, amount: h.deOil * 0.7)
        }
        if h.smooth > 0 {
            let soft = out.clampedToExtent().applyingGaussianBlur(sigma: Double(min(e.width, e.height)) * 0.003 * (1 + h.smooth * 3)).cropped(to: e)
            out = blend(soft, over: out, mask: mask, amount: h.smooth * 0.8)
        }
        if h.rootRetouch > 0 { out = roots(h, out, mask: mask) }
        return out
    }

    /// Darken the upper part of the hair mask (toward the scalp) with a gradient.
    private static func roots(_ h: HairRetouch, _ image: CIImage, mask: CIImage) -> CIImage {
        let e = image.extent
        let g = CIFilter.linearGradient()
        g.point0 = CGPoint(x: e.midX, y: e.maxY); g.point1 = CGPoint(x: e.midX, y: e.midY + e.height * 0.1)
        g.color0 = CIColor(red: 1, green: 1, blue: 1); g.color1 = CIColor(red: 0, green: 0, blue: 0)
        guard let ramp = g.outputImage?.cropped(to: e) else { return image }
        let band = ramp.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: e)
        let darker = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.18 * h.rootRetouch, kCIInputSaturationKey: 1 - 0.1 * h.rootRetouch])
        return blend(darker, over: image, mask: band, amount: h.rootRetouch)
    }

    private static func blend(_ edited: CIImage, over base: CIImage, mask: CIImage, amount: Double) -> CIImage {
        let k = CGFloat(min(max(amount, 0), 1))
        let m = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)])
        let f = CIFilter.blendWithMask(); f.inputImage = edited.cropped(to: base.extent); f.backgroundImage = base; f.maskImage = m
        return f.outputImage?.cropped(to: base.extent) ?? base
    }
}
