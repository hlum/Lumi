import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

/// Hair estimate without a dedicated model: the person's pixels that sit around and above the face, minus the face itself.
enum HairMask {
    /// Head region for a face box (normalized, y-down): wider than the face, extending well above it and a little below the chin line.
    static func headRegion(face: CGRect) -> CGRect {
        let w = face.width * 1.9, h = face.height * 1.85
        return CGRect(x: face.midX - w / 2, y: face.minY - face.height * 0.75, width: w, height: h)
    }

    /// `person`: white = person (same extent as `image`). `face`: Vision-space box (normalized, origin bottom-left).
    static func estimate(person: CIImage, face: FaceInfo, image: CIImage? = nil) -> CIImage {
        let e = person.extent
        let box = MakeupRenderer.faceBox(face)                                     // y-down
        let head = headRegion(face: box)
        // region mask (Vision space is bottom-left, so flip y)
        func rectMask(_ r: CGRect, gray: CGFloat) -> CGRect {
            CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
        }
        let headMask = ellipseMask(rectMask(head, gray: 1), extent: e)
        // the face itself is not hair
        let faceCut = SkinMask.make(face: face, size: e.size, feather: 0.01) ?? CIImage(color: .black).cropped(to: e)
        var hair = person.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: headMask]).cropped(to: e)
        if let image, let gate = colorGate(image: image, person: person, box: box) {
            hair = hair.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: gate]).cropped(to: e)
        }
        let result = subtract(hair, faceCut)
        return result.clampedToExtent().applyingGaussianBlur(sigma: Double(min(e.width, e.height)) * 0.004).cropped(to: e)
    }

    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])

    /// Hair is the person's pixels near the hair's own colour, sampled just above the forehead; skin, clothes and
    /// background inside the head region fall away. nil when no hair is found there (bald, hat, cropped).
    static func colorGate(image: CIImage, person: CIImage, box: CGRect) -> CIImage? {
        let e = image.extent
        let strip = CGRect(x: box.midX - box.width * 0.3, y: box.minY - box.height * 0.22, width: box.width * 0.6, height: box.height * 0.25)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard strip.width > 0.005, strip.height > 0.005 else { return nil }
        let r = CGRect(x: e.minX + strip.minX * e.width, y: e.minY + (1 - strip.maxY) * e.height, width: strip.width * e.width, height: strip.height * e.height)
        func average(_ i: CIImage) -> [Float] {
            var px = [Float](repeating: 0, count: 4)
            ctx.render(i.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: r)]), toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
            return px
        }
        let weight = average(person)[0]
        guard weight > 0.15 else { return nil }
        // person-weighted mean colour: mean(image * person) / mean(person)
        let weighted = average(image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: person]))
        let ref = CIColor(red: CGFloat(min(weighted[0] / weight, 1)), green: CGFloat(min(weighted[1] / weight, 1)), blue: CGFloat(min(weighted[2] / weight, 1)))
        let diff = CIImage(color: ref).cropped(to: e).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        let (t0, w): (CGFloat, CGFloat) = (0.10, 0.25)                      // full match up to t0, none beyond t0 + w (sum of |dR|+|dG|+|dB|)
        let k = -1 / w, v = CIVector(x: k, y: k, z: k, w: 0)
        return diff.applyingFilter("CIColorMatrix", parameters: ["inputRVector": v, "inputGVector": v, "inputBVector": v, "inputBiasVector": CIVector(x: 1 + t0 / w, y: 1 + t0 / w, z: 1 + t0 / w, w: 0)])
            .applyingFilter("CIColorClamp").cropped(to: e)
    }

    private static func subtract(_ a: CIImage, _ b: CIImage) -> CIImage {
        // a - b, clamped at 0
        let f = CIFilter.subtractBlendMode(); f.inputImage = b; f.backgroundImage = a
        return f.outputImage?.cropped(to: a.extent) ?? a
    }

    private static func ellipseMask(_ r: CGRect, extent e: CGRect) -> CIImage {
        let w = Int(e.width), h = Int(e.height)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return CIImage(color: .black).cropped(to: e) }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillEllipse(in: CGRect(x: r.minX * e.width, y: r.minY * e.height, width: r.width * e.width, height: r.height * e.height))
        return ctx.makeImage().map { CIImage(cgImage: $0) } ?? CIImage(color: .black).cropped(to: e)
    }

    /// Combine the estimate with brush edits: painted = add, erased = remove.
    static func refine(_ estimate: CIImage, add: MaskCanvas?, remove: MaskCanvas?) -> CIImage {
        var m = estimate
        let e = estimate.extent
        if let add { m = MaskScaling.scaled(add, to: e).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: m]).cropped(to: e) }
        if let remove { m = subtract(m, MaskScaling.scaled(remove, to: e)) }
        return m
    }
}

struct HairColorParams: Codable, Equatable {
    var color = RGBA(r: 0.55, g: 0.25, b: 0.1, a: 1)
    var strength = 0.0        // 0...1
    var keepShine = 0.5       // 0...1 how much of the original highlights survive
    var isIdentity: Bool { strength <= 0 }
}

enum HairOps {
    /// Recolors only where `mask` is set. Uses color blend (hue + saturation of the dye, luminance of the hair) so strands and shine remain.
    static func recolor(_ p: HairColorParams, image: CIImage, mask: CIImage) -> CIImage {
        guard !p.isIdentity else { return image }
        let e = image.extent
        let dye = CIImage(color: CIColor(red: p.color.r, green: p.color.g, blue: p.color.b)).cropped(to: e)
        let tinted = dye.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
        // bring back highlights: lighten the result toward the original where the original is bright
        let shine = min(max(p.keepShine, 0), 1)
        let withShine: CIImage
        if shine > 0 {
            let mix = CIFilter.dissolveTransition(); mix.inputImage = tinted; mix.targetImage = image; mix.time = Float(shine * 0.25)
            withShine = mix.outputImage?.cropped(to: e) ?? tinted
        } else { withShine = tinted }
        let s = min(max(p.strength, 0), 1)
        let scaledMask = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: s, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: s, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: s, w: 0)])
        let blend = CIFilter.blendWithMask(); blend.inputImage = withShine; blend.backgroundImage = image; blend.maskImage = scaledMask
        return blend.outputImage?.cropped(to: e) ?? image
    }
}
