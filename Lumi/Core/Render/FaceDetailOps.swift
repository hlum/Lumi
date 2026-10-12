import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

struct FaceDetailParams: Codable, Equatable {
    var flash = 0.0            // 0...1 AI flash / fill light on the face
    var underEye = 0.0         // 0...1 brighten and soften under-eye circles
    var wrinkles = 0.0         // 0...1 soften fine lines around eyes and mouth
    var teethWhiten = 0.0      // 0...1
    var eyeBright = 0.0        // 0...1 brighter, clearer eyes
    var eyeBags = 0.0          // 0...1 flatten puffiness under the eyes
    var tearTroughs = 0.0      // 0...1 fill the hollow by the inner eye corner
    var smileLines = 0.0       // 0...1 soften lines from nose to mouth corners
    var eyeLines = 0.0         // 0...1 soften crow's feet
    var contactAmount = 0.0    // 0...1 colored contact lenses
    var contactColor = RGBA(r: 0.35, g: 0.5, b: 0.75, a: 1)
    var catchlight = 0.0       // 0...1 small light reflection in each eye

    var isIdentity: Bool {
        flash == 0 && underEye == 0 && wrinkles == 0 && teethWhiten == 0 && eyeBright == 0 && eyeBags == 0 && tearTroughs == 0
            && smileLines == 0 && eyeLines == 0 && contactAmount == 0 && catchlight == 0
    }
}

extension FaceDetailParams {
    /// Old drafts have only the first five values.
    init(from decoder: Decoder) throws {
        enum K: String, CodingKey { case flash, underEye, wrinkles, teethWhiten, eyeBright, eyeBags, tearTroughs, smileLines, eyeLines, contactAmount, contactColor, catchlight }
        let c = try decoder.container(keyedBy: K.self)
        self.init()
        func d(_ k: K) throws -> Double { try c.decodeIfPresent(Double.self, forKey: k) ?? 0 }
        flash = try d(.flash); underEye = try d(.underEye); wrinkles = try d(.wrinkles); teethWhiten = try d(.teethWhiten); eyeBright = try d(.eyeBright)
        eyeBags = try d(.eyeBags); tearTroughs = try d(.tearTroughs); smileLines = try d(.smileLines); eyeLines = try d(.eyeLines)
        contactAmount = try d(.contactAmount); catchlight = try d(.catchlight)
        contactColor = try c.decodeIfPresent(RGBA.self, forKey: .contactColor) ?? contactColor
    }
}

enum FaceDetailOps {
    // MARK: masks (image-normalized, y-down geometry -> CI image masks)

    private static func polygonMask(_ polys: [[CGPoint]], size: CGSize, feather: CGFloat) -> CIImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0, polys.contains(where: { $0.count >= 3 }),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        for p in polys where p.count >= 3 {
            ctx.addLines(between: p.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }); ctx.closePath(); ctx.fillPath()
        }
        guard let cg = ctx.makeImage() else { return nil }
        let m = CIImage(cgImage: cg)
        return feather > 0 ? m.clampedToExtent().applyingGaussianBlur(sigma: Double(min(size.width, size.height) * feather)).cropped(to: m.extent) : m
    }

    private static func scaled(_ p: [CGPoint], about c: CGPoint, x: CGFloat, y: CGFloat) -> [CGPoint] {
        p.map { CGPoint(x: c.x + ($0.x - c.x) * x, y: c.y + ($0.y - c.y) * y) }
    }

    /// Region just below each eye (a flattened crescent under the eye outline).
    static func underEyeMask(_ face: FaceInfo, size: CGSize) -> CIImage? {
        var polys: [[CGPoint]] = []
        for region in ["leftEye", "rightEye"] {
            let pts = FaceReshape.points(face, region)
            guard let c = FaceReshape.center(pts), FaceReshape.width(pts) > 0 else { continue }
            let w = FaceReshape.width(pts)
            let below = scaled(pts, about: c, x: 1.3, y: 1.0).map { CGPoint(x: $0.x, y: $0.y + w * 0.35) }
            polys.append(below)
        }
        return polygonMask(polys, size: size, feather: 0.012)
    }

    /// The visible teeth: the inner-lip opening.
    static func teethMask(_ face: FaceInfo, size: CGSize) -> CIImage? {
        let inner = FaceReshape.points(face, "innerLips")
        guard inner.count >= 3, let c = FaceReshape.center(inner) else { return nil }
        return polygonMask([scaled(inner, about: c, x: 0.92, y: 0.8)], size: size, feather: 0.003)
    }

    static func eyeMask(_ face: FaceInfo, size: CGSize) -> CIImage? {
        let polys = ["leftEye", "rightEye"].compactMap { r -> [CGPoint]? in
            let p = FaceReshape.points(face, r); guard let c = FaceReshape.center(p) else { return nil }
            return scaled(p, about: c, x: 0.95, y: 0.95)
        }
        return polygonMask(polys, size: size, feather: 0.004)
    }

    /// Lines around the eyes (crow's feet) and mouth corners, as soft blobs.
    static func wrinkleMask(_ face: FaceInfo, size: CGSize, eyes: Bool = true, mouth: Bool = true) -> CIImage? {
        var polys: [[CGPoint]] = []
        if eyes { for (region, side) in [("leftEye", -1.0), ("rightEye", 1.0)] {
            let pts = FaceReshape.points(face, region)
            guard let c = FaceReshape.center(pts) else { continue }
            let w = FaceReshape.width(pts)
            let o = CGPoint(x: c.x + CGFloat(side) * w * 0.85, y: c.y + w * 0.1)
            polys.append((0..<12).map { CGPoint(x: o.x + w * 0.45 * cos(Double($0) * .pi / 6), y: o.y + w * 0.35 * sin(Double($0) * .pi / 6)) })
        } }
        let lips = FaceReshape.points(face, "outerLips")
        if mouth, let c = FaceReshape.center(lips), FaceReshape.width(lips) > 0 {
            let w = FaceReshape.width(lips)
            for side in [-1.0, 1.0] { polys.append((0..<12).map { CGPoint(x: c.x + CGFloat(side) * w * 0.65 + w * 0.2 * cos(Double($0) * .pi / 6), y: c.y - w * 0.1 + w * 0.3 * sin(Double($0) * .pi / 6)) }) }
        }
        return polygonMask(polys, size: size, feather: 0.01)
    }

    /// The iris of each eye: a circle around the eye's center, only where the eye is open.
    static func irisMask(_ face: FaceInfo, size: CGSize, radiusScale: CGFloat = 0.21) -> CIImage? {
        var polys: [[CGPoint]] = []
        for region in ["leftEye", "rightEye"] {
            let pts = FaceReshape.points(face, region)
            guard let c = FaceReshape.center(pts), FaceReshape.width(pts) > 0 else { continue }
            let r = FaceReshape.width(pts) * radiusScale * (size.width / max(size.height, 1) > 0 ? 1 : 1)
            // image-normalized y-down; x radius in width units, y radius corrected for the aspect
            let aspect = size.width / max(size.height, 1)
            polys.append((0..<24).map { CGPoint(x: c.x + r * cos(Double($0) * .pi / 12), y: c.y + r * aspect * sin(Double($0) * .pi / 12)) })
        }
        guard let circles = polygonMask(polys, size: size, feather: 0.0015), let open = eyeMask(face, size: size) else { return nil }
        return circles.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: open]).cropped(to: circles.extent)
    }

    /// A small round highlight up and to the side of each eye's center.
    static func catchlightMask(_ face: FaceInfo, size: CGSize) -> CIImage? {
        var polys: [[CGPoint]] = []
        for region in ["leftEye", "rightEye"] {
            let pts = FaceReshape.points(face, region)
            guard let c = FaceReshape.center(pts), FaceReshape.width(pts) > 0 else { continue }
            let w = FaceReshape.width(pts), aspect = size.width / max(size.height, 1)
            let o = CGPoint(x: c.x - w * 0.07, y: c.y - w * 0.07 * aspect)
            polys.append((0..<16).map { CGPoint(x: o.x + w * 0.06 * cos(Double($0) * .pi / 8), y: o.y + w * 0.06 * aspect * sin(Double($0) * .pi / 8)) })
        }
        return polygonMask(polys, size: size, feather: 0.002)
    }

    /// The hollow beside the nose end of each eye, just under it.
    static func tearTroughMask(_ face: FaceInfo, size: CGSize) -> CIImage? {
        var polys: [[CGPoint]] = []
        let aspect = size.width / max(size.height, 1)
        let eyes = ["leftEye", "rightEye"].map { FaceReshape.points(face, $0) }.filter { !$0.isEmpty }
        let mid = eyes.compactMap { FaceReshape.center($0)?.x }.reduce(0, +) / CGFloat(max(eyes.count, 1))
        for pts in eyes {
            guard let c = FaceReshape.center(pts) else { continue }
            let w = FaceReshape.width(pts)
            let inner = CGPoint(x: c.x + (mid - c.x) * 0.55, y: c.y + w * 0.4 * aspect)
            polys.append((0..<12).map { CGPoint(x: inner.x + w * 0.3 * cos(Double($0) * .pi / 6), y: inner.y + w * 0.16 * aspect * sin(Double($0) * .pi / 6)) })
        }
        return polygonMask(polys, size: size, feather: 0.008)
    }

    // MARK: apply

    private static func blend(_ edited: CIImage, over base: CIImage, mask: CIImage, amount: Double) -> CIImage {
        let k = CGFloat(min(max(amount, 0), 1))
        let m = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)])
        let f = CIFilter.blendWithMask(); f.inputImage = edited.cropped(to: base.extent); f.backgroundImage = base; f.maskImage = m
        return f.outputImage?.cropped(to: base.extent) ?? base
    }

    static func apply(_ p: FaceDetailParams, to image: CIImage, face: FaceInfo) -> CIImage {
        guard !p.isIdentity else { return image }
        let size = image.extent.size
        var out = image

        if p.flash > 0, let skin = SkinMask.make(face: face, size: size, feather: 0.04) {
            // flash look: lift exposure, add contrast and a soft highlight, fading toward the face edge
            let ev = CIFilter.exposureAdjust(); ev.inputImage = out; ev.ev = Float(p.flash * 0.9)
            let c = CIFilter.colorControls(); c.inputImage = ev.outputImage; c.contrast = Float(1 + p.flash * 0.15); c.saturation = Float(1 - p.flash * 0.05)
            out = blend(c.outputImage ?? out, over: out, mask: skin, amount: 1)
        }
        if p.underEye > 0, let m = underEyeMask(face, size: size) {
            let lift = CIFilter.colorControls(); lift.inputImage = out; lift.brightness = Float(p.underEye * 0.12)
            let soft = (lift.outputImage ?? out).clampedToExtent().applyingGaussianBlur(sigma: Double(min(size.width, size.height)) * 0.004 * p.underEye).cropped(to: out.extent)
            out = blend(soft, over: out, mask: m, amount: p.underEye)
        }
        if p.eyeBags > 0, let m = underEyeMask(face, size: size) {
            // puffiness: replace the area with a heavily smoothed copy, slightly lifted
            let soft = out.clampedToExtent().applyingGaussianBlur(sigma: Double(min(size.width, size.height)) * 0.012 * p.eyeBags).cropped(to: out.extent)
            let lift = CIFilter.colorControls(); lift.inputImage = soft; lift.brightness = Float(p.eyeBags * 0.04)
            out = blend(lift.outputImage ?? soft, over: out, mask: m, amount: p.eyeBags)
        }
        if p.tearTroughs > 0, let m = tearTroughMask(face, size: size) {
            let lift = CIFilter.colorControls(); lift.inputImage = out; lift.brightness = Float(p.tearTroughs * 0.14); lift.saturation = Float(1 - p.tearTroughs * 0.15)
            let soft = (lift.outputImage ?? out).clampedToExtent().applyingGaussianBlur(sigma: Double(min(size.width, size.height)) * 0.004).cropped(to: out.extent)
            out = blend(soft, over: out, mask: m, amount: p.tearTroughs)
        }
        for (amount, eyes, mouth) in [(p.eyeLines, true, false), (p.smileLines, false, true)] where amount > 0 {
            if let m = wrinkleMask(face, size: size, eyes: eyes, mouth: mouth) {
                let soft = out.clampedToExtent().applyingGaussianBlur(sigma: Double(min(size.width, size.height)) * 0.007).cropped(to: out.extent)
                out = blend(soft, over: out, mask: m, amount: amount * 0.85)
            }
        }
        if p.wrinkles > 0, let m = wrinkleMask(face, size: size) {
            let soft = out.clampedToExtent().applyingGaussianBlur(sigma: Double(min(size.width, size.height)) * 0.006).cropped(to: out.extent)
            out = blend(soft, over: out, mask: m, amount: p.wrinkles * 0.8)
        }
        if p.teethWhiten > 0, let m = teethMask(face, size: size) {
            let w = CIFilter.colorControls(); w.inputImage = out; w.saturation = Float(1 - p.teethWhiten * 0.7); w.brightness = Float(p.teethWhiten * 0.1)
            out = blend(w.outputImage ?? out, over: out, mask: m, amount: 1)
        }
        if p.contactAmount > 0, let m = irisMask(face, size: size) {
            // the lens takes the colour's hue and saturation and keeps the iris's own light and dark; a small lift so pale colours show on dark eyes
            let tint = CIImage(color: CIColor(red: p.contactColor.r, green: p.contactColor.g, blue: p.contactColor.b)).cropped(to: out.extent)
            let lifted = CIFilter.exposureAdjust(); lifted.inputImage = out; lifted.ev = 0.7
            let colored = tint.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: lifted.outputImage ?? out]).cropped(to: out.extent)
            out = blend(colored, over: out, mask: m, amount: p.contactAmount)
        }
        if p.catchlight > 0, let m = catchlightMask(face, size: size) {
            out = blend(CIImage(color: .white).cropped(to: out.extent), over: out, mask: m, amount: p.catchlight * 0.9)
        }
        if p.eyeBright > 0, let m = eyeMask(face, size: size) {
            let b = CIFilter.colorControls(); b.inputImage = out; b.brightness = Float(p.eyeBright * 0.08); b.contrast = Float(1 + p.eyeBright * 0.2)
            out = blend(b.outputImage ?? out, over: out, mask: m, amount: 1)
        }
        return out
    }
}
