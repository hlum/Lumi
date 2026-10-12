import CoreImage
import CoreImage.CIFilterBuiltins

enum RelightStyle: String, Codable, CaseIterable {
    // AI Flash
    case flash, fillLight, night, backlit
    // coloured light on the person
    case photoBooth, ledStrip, redLight, goldenHour

    static let aiFlash: [RelightStyle] = [.flash, .fillLight, .night, .backlit]
    static let coloured: [RelightStyle] = [.ledStrip, .redLight, .photoBooth, .goldenHour]

    var title: String {
        switch self {
        case .flash: "Flash"; case .fillLight: "Fill light"; case .night: "Night"; case .backlit: "Backlit face"
        case .photoBooth: "Photo booth"; case .ledStrip: "LED strip"; case .redLight: "Red room"; case .goldenHour: "Golden hour"
        }
    }
    var look: RelightLook? {
        switch self { case .photoBooth: .photoBooth; case .ledStrip: .ledStrip; case .redLight: .redLight; case .goldenHour: .goldenHour; default: nil }
    }
}

struct RelightConfig: Codable, Equatable {
    var style = RelightStyle.flash
    var strength = 0.0                 // 0 = off
    var erase: MaskCanvas?             // painted areas get the unlit picture back
    var isIdentity: Bool { strength <= 0 }
}

enum RelightOps {
    /// Soft ellipses over each face, a bit larger than the face, for styles that light the face rather than the whole person.
    static func faceMask(_ faces: [FaceInfo], size: CGSize, grow: CGFloat = 1.5) -> CIImage? {
        guard !faces.isEmpty, size.width > 0, size.height > 0,
              let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: Int(size.width), space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        for f in faces {
            let b = MakeupRenderer.faceBox(f), w = b.width * grow, h = b.height * grow
            ctx.fillEllipse(in: CGRect(x: (b.midX - w / 2) * size.width, y: (1 - b.midY - h / 2) * size.height, width: w * size.width, height: h * size.height))
        }
        guard let cg = ctx.makeImage() else { return nil }
        let m = CIImage(cgImage: cg)
        return m.clampedToExtent().applyingGaussianBlur(sigma: Double(min(size.width, size.height)) * 0.06).cropped(to: m.extent)
    }

    private static func exposure(_ image: CIImage, _ ev: Float) -> CIImage {
        let f = CIFilter.exposureAdjust(); f.inputImage = image; f.ev = ev
        return f.outputImage ?? image
    }

    private static func blend(_ edited: CIImage, over base: CIImage, mask: CIImage?, amount: Double) -> CIImage {
        let k = CGFloat(min(max(amount, 0), 1)), e = base.extent
        let m = (mask ?? CIImage(color: .white).cropped(to: e)).applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)])
        let f = CIFilter.blendWithMask(); f.inputImage = edited.cropped(to: e); f.backgroundImage = base; f.maskImage = m
        return f.outputImage?.cropped(to: e) ?? base
    }

    /// `personMask`: white where the person is (nil = treat everyone as lit). `faces`: for the face-only styles.
    static func apply(_ c: RelightConfig, to image: CIImage, faces: [FaceInfo], personMask: CIImage?) -> CIImage {
        guard !c.isIdentity else { return image }
        let e = image.extent, s = min(max(c.strength, 0), 1)
        var out = image
        switch c.style {
        case .flash:
            // the subject gets a hard, bright, slightly cool light; what is behind it falls off
            let subject = personMask ?? faceMask(faces, size: e.size, grow: 2.2)
            let lit = AdjustOps.curved(exposure(image, Float(0.9 * s)), ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.22), CGPoint(x: 0.75, y: 0.8), CGPoint(x: 1, y: 1)]))
            let cool = lit.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.98, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1.02, w: 0)])
            out = blend(cool, over: image, mask: subject, amount: s)
            if subject != nil {
                let dark = exposure(out, Float(-0.55 * s))
                let inverted = subject!.applyingFilter("CIColorInvert")
                out = blend(dark, over: out, mask: inverted, amount: 1)
            }
        case .fillLight:
            let subject = personMask ?? faceMask(faces, size: e.size, grow: 2.2)
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = image; f.shadowAmount = Float(0.9 * s); f.highlightAmount = 1
            let warm = (f.outputImage ?? image).applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1.02, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0.98, w: 0)])
            out = blend(warm, over: image, mask: subject, amount: 1)
        case .night:
            // a dark scene made readable: shadows up, a touch cooler and cleaner, light sources held back
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = image; f.shadowAmount = Float(0.8 * s); f.highlightAmount = Float(1 - 0.3 * s)
            var lit = exposure(f.outputImage ?? image, Float(0.5 * s))
            let n = CIFilter.noiseReduction(); n.inputImage = lit; n.noiseLevel = Float(0.02 + 0.03 * s); n.sharpness = 0.4
            lit = n.outputImage ?? lit
            out = lit.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1 - 0.03 * s, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1 + 0.04 * s, w: 0)]).cropped(to: e)
        case .backlit:
            // the face against a bright sky: brighten and open it up, nothing else
            let mask = faceMask(faces, size: e.size, grow: 1.3) ?? personMask
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = exposure(image, Float(1.1 * s)); f.shadowAmount = Float(0.6 * s); f.highlightAmount = 1
            out = blend(f.outputImage ?? image, over: image, mask: mask, amount: 1)
        case .photoBooth, .ledStrip, .redLight, .goldenHour:
            out = c.style.look?.apply(to: image, personMask: personMask ?? faceMask(faces, size: e.size, grow: 2.2), strength: s) ?? image
        }
        // painted areas keep the unlit picture
        if let erase = c.erase, !erase.isEmpty {
            let f = CIFilter.blendWithMask(); f.inputImage = image; f.backgroundImage = out; f.maskImage = MaskScaling.scaled(erase, to: e)
            out = f.outputImage?.cropped(to: e) ?? out
        }
        return out.cropped(to: e)
    }
}

/// Classic one-slider effects as a document step.
struct PhotoEffectConfig: Codable, Equatable {
    var effect = PhotoEffect.glitch
    var strength = 0.0
    var isIdentity: Bool { strength <= 0 }
}
