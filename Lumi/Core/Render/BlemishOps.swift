import CoreImage
import CoreImage.CIFilterBuiltins

/// A spot the user tapped to heal (or the auto finder's pick). Normalized, y-down; `r` is a fraction of the picture's width.
struct HealSpot: Codable, Equatable { var x: Double, y: Double, r: Double }

struct BlemishParams: Codable, Equatable {
    var spots = 0.0            // 0...1 find and heal small dark spots on every face
    var concealer = 0.0        // 0...1 even out larger darker patches
    var redness = 0.0          // 0...1 calm red patches
    var manual: [HealSpot] = []
    var isIdentity: Bool { spots == 0 && concealer == 0 && redness == 0 && manual.isEmpty }

    init() {}
    enum CodingKeys: String, CodingKey { case spots, concealer, redness, manual }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        spots = try c.decodeIfPresent(Double.self, forKey: .spots) ?? 0
        concealer = try c.decodeIfPresent(Double.self, forKey: .concealer) ?? 0
        redness = try c.decodeIfPresent(Double.self, forKey: .redness) ?? 0
        manual = try c.decodeIfPresent([HealSpot].self, forKey: .manual) ?? []
    }
}

enum BlemishOps {
    private static let ctx = CIContext(options: [.workingColorSpace: NSNull()])

    /// Luminance bitmap of `region` (CI pixels), at most `maxSide` on its long side. Returns the image and the scale from its pixels to the source's.
    static func gray(_ image: CIImage, region: CGRect, maxSide: CGFloat = 640) -> (GrayImage, scale: CGFloat)? {
        let r = region.intersection(image.extent).integral
        guard r.width >= 8, r.height >= 8 else { return nil }
        let k = min(1, maxSide / max(r.width, r.height))
        let w = max(Int((r.width * k).rounded()), 1), h = max(Int((r.height * k).rounded()), 1)
        let scaled = image.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(w) / r.width, y: CGFloat(h) / r.height))
        var px = [UInt8](repeating: 0, count: w * h)
        let g = scaled.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        ctx.render(g, toBitmap: &px, rowBytes: w, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .R8, colorSpace: nil)
        // bitmap rows come out top-first, like the picture
        return (GrayImage(width: w, height: h, pixels: px), 1 / k)
    }

    /// Spots inside one face, in the picture's own pixels (y-down, relative to the whole image).
    static func detect(in image: CIImage, face: FaceInfo, sensitivity: Double, largeBlotches: Bool = false) -> [SpotDetector.Spot] {
        let e = image.extent
        let box = MakeupRenderer.faceBox(face)
        let region = CGRect(x: e.minX + box.minX * e.width, y: e.minY + (1 - box.maxY) * e.height, width: box.width * e.width, height: box.height * e.height)
        guard let (g, scale) = gray(image, region: region) else { return [] }
        let found: [SpotDetector.Spot]
        if largeBlotches {
            found = SpotDetector.detect(g, window: max(g.width / 5, 15) | 1, threshold: Int(14 - 6 * sensitivity), minArea: 40, maxArea: g.width * g.height / 12)
        } else {
            found = SpotDetector.detect(g, window: max(g.width / 22, 9) | 1, threshold: Int(22 - 12 * sensitivity), minArea: 3, maxArea: max(g.width * g.height / 400, 60))
        }
        // never "heal" the eyes, brows, lips or nostrils: those dark parts are meant to be there
        let keepOut = ["leftEye", "rightEye", "leftEyebrow", "rightEyebrow", "outerLips", "nose"].map { r -> CGRect in
            let p = FaceReshape.points(face, r)
            guard let x0 = p.map(\.x).min(), let x1 = p.map(\.x).max(), let y0 = p.map(\.y).min(), let y1 = p.map(\.y).max() else { return .null }
            return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).insetBy(dx: -(x1 - x0) * 0.15, dy: -(x1 - x0) * 0.15)
        }
        return found.compactMap { s in
            let nx = box.minX + (s.center.x / CGFloat(g.width)) * box.width, ny = box.minY + (s.center.y / CGFloat(g.height)) * box.height
            if keepOut.contains(where: { $0.contains(CGPoint(x: nx, y: ny)) }) { return nil }
            return SpotDetector.Spot(center: CGPoint(x: (nx * e.width), y: (ny * e.height)), radius: s.radius * Double(scale), area: s.area)
        }
    }

    static func apply(_ p: BlemishParams, to image: CIImage, faces: [FaceInfo]) -> CIImage {
        guard !p.isIdentity else { return image }
        let e = image.extent
        var out = image
        for face in faces {
            if p.spots > 0 { out = HealOps.apply(detect(in: out, face: face, sensitivity: p.spots), to: out, amount: p.spots) }
            if p.concealer > 0 { out = HealOps.apply(detect(in: out, face: face, sensitivity: p.concealer, largeBlotches: true), to: out, amount: p.concealer) }
            if p.redness > 0, let skin = SkinMask.make(face: face, size: e.size, feather: 0.02) { out = calmRedness(out, mask: skin, amount: p.redness) }
        }
        if !p.manual.isEmpty {
            let spots = p.manual.map { SpotDetector.Spot(center: CGPoint(x: $0.x * e.width, y: $0.y * e.height), radius: max($0.r * e.width, 2), area: 0) }
            out = HealOps.apply(spots, to: out, amount: 1)
        }
        return out
    }

    /// Pulls red patches toward the surrounding skin tone: where red clearly exceeds green, saturation drops and warmth cools a little.
    static func calmRedness(_ image: CIImage, mask: CIImage, amount: Double) -> CIImage {
        let e = image.extent
        let a = CGFloat(min(max(amount, 0), 1))
        // redness = (r - g) pushed through a ramp, limited to the skin mask
        let redness = image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 4, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: -4, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: -0.35, y: 0, z: 0, w: 0)])
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0)]).applyingFilter("CIColorClamp").cropped(to: e)
        let m = redness.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask]).applyingGaussianBlur(sigma: 2).cropped(to: e)
        let calmer = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1 - 0.6 * a])
        let f = CIFilter.blendWithMask(); f.inputImage = calmer; f.backgroundImage = image; f.maskImage = m
        return f.outputImage?.cropped(to: e) ?? image
    }
}
