import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

struct MakeupParams: Codable, Equatable {
    enum Finish: String, Codable { case matte, satin, gloss }
    enum BlushStyle: String, Codable { case round, oval, wide }

    var lipColor = RGBA(r: 0.8, g: 0.15, b: 0.25, a: 1)
    var lipOpacity = 0.0
    var lipFinish = Finish.satin
    var ombre = 0.0                 // 0...1: fades the color from the lip edge to a lighter center
    var blushColor = RGBA(r: 0.95, g: 0.4, b: 0.45, a: 1)
    var blushOpacity = 0.0
    var blushStyle = BlushStyle.round
    var contour = 0.0               // 0...1 shadow under the cheekbones and along the jaw
    var highlight = 0.0             // 0...1 light on the nose bridge and cheekbones
    var foundation = 0.0            // 0...1 evens out skin color across the face
    var isIdentity: Bool { lipOpacity == 0 && blushOpacity == 0 && contour == 0 && highlight == 0 && foundation == 0 }

    init() {}
    enum CodingKeys: String, CodingKey { case lipColor, lipOpacity, lipFinish, ombre, blushColor, blushOpacity, blushStyle, contour, highlight, foundation }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        lipColor = try c.decodeIfPresent(RGBA.self, forKey: .lipColor) ?? lipColor
        lipOpacity = try c.decodeIfPresent(Double.self, forKey: .lipOpacity) ?? 0
        lipFinish = try c.decodeIfPresent(Finish.self, forKey: .lipFinish) ?? .satin
        ombre = try c.decodeIfPresent(Double.self, forKey: .ombre) ?? 0
        blushColor = try c.decodeIfPresent(RGBA.self, forKey: .blushColor) ?? blushColor
        blushOpacity = try c.decodeIfPresent(Double.self, forKey: .blushOpacity) ?? 0
        blushStyle = try c.decodeIfPresent(BlushStyle.self, forKey: .blushStyle) ?? .round
        contour = try c.decodeIfPresent(Double.self, forKey: .contour) ?? 0
        highlight = try c.decodeIfPresent(Double.self, forKey: .highlight) ?? 0
        foundation = try c.decodeIfPresent(Double.self, forKey: .foundation) ?? 0
    }
}

enum MakeupRenderer {
    // MARK: geometry (image-normalized, y-down)

    struct Spot: Equatable { var center: CGPoint; var radius: Double; var squash: Double }   // squash: y radius / x radius

    /// Blush sits under each eye, nudged toward the ear and clamped inside the face box.
    static func blushSpots(_ face: FaceInfo, style: MakeupParams.BlushStyle) -> [Spot] {
        let box = faceBox(face)
        var out: [Spot] = []
        for (region, outward) in [("leftEye", -1.0), ("rightEye", 1.0)] {
            let pts = FaceReshape.points(face, region)
            guard let c = FaceReshape.center(pts) else { continue }
            let w = Double(box.width), h = Double(box.height)
            let x = min(max(Double(c.x) + outward * w * 0.08, Double(box.minX)), Double(box.maxX))
            let y = min(max(Double(c.y) + h * 0.18, Double(box.minY)), Double(box.maxY))
            let r: Double, sq: Double
            switch style { case .round: (r, sq) = (w * 0.14, 1); case .oval: (r, sq) = (w * 0.16, 0.6); case .wide: (r, sq) = (w * 0.2, 0.5) }
            out.append(Spot(center: CGPoint(x: x, y: y), radius: r, squash: sq))
        }
        return out
    }

    /// The face box converted to y-down image space.
    /// A y-down normalized rect as a Core Image (y-up) pixel rect.
    static func ciRect(_ r: CGRect, size: CGSize) -> CGRect {
        CGRect(x: r.minX * size.width, y: (1 - r.maxY) * size.height, width: r.width * size.width, height: r.height * size.height)
    }

    static func faceBox(_ face: FaceInfo) -> CGRect {
        CGRect(x: face.box.minX, y: 1 - face.box.maxY, width: face.box.width, height: face.box.height)
    }

    // MARK: contour, highlight and foundation regions

    /// Soft ellipses (image-normalized, y-down) for contour: the hollows under the cheekbones, toward the ears.
    static func contourSpots(_ face: FaceInfo) -> [Spot] {
        let box = faceBox(face)
        return blushSpots(face, style: .wide).map { b in
            let outward: CGFloat = b.center.x < box.midX ? -1 : 1
            return Spot(center: CGPoint(x: b.center.x + outward * box.width * 0.12, y: b.center.y + box.height * 0.1), radius: b.radius * 0.8, squash: 0.45)
        }
    }

    /// Highlight: the nose bridge and the top of each cheekbone.
    static func highlightSpots(_ face: FaceInfo) -> [Spot] {
        let box = faceBox(face)
        var out: [Spot] = []
        let nose = FaceReshape.points(face, "nose")
        if let c = FaceReshape.center(nose) { out.append(Spot(center: CGPoint(x: c.x, y: c.y - box.height * 0.08), radius: box.width * 0.07, squash: 2.2)) }
        for b in blushSpots(face, style: .oval) { out.append(Spot(center: CGPoint(x: b.center.x, y: b.center.y - box.height * 0.1), radius: b.radius * 0.7, squash: 0.5)) }
        return out
    }

    static func spotsMask(_ spots: [Spot], size: CGSize) -> CIImage? {
        guard !spots.isEmpty, size.width > 0, size.height > 0 else { return nil }
        var mask = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        for s in spots {
            let r = s.radius * Double(size.width)
            let g = CIFilter.radialGradient()
            g.center = CGPoint(x: 0, y: 0); g.radius0 = Float(r * 0.1); g.radius1 = Float(r); g.color0 = .white; g.color1 = .black
            guard var spot = g.outputImage?.cropped(to: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)) else { continue }
            spot = spot.transformed(by: CGAffineTransform(scaleX: 1, y: s.squash))
                .transformed(by: CGAffineTransform(translationX: s.center.x * size.width, y: (1 - s.center.y) * size.height))
            mask = spot.composited(over: CIImage(color: .clear).cropped(to: mask.extent)).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: mask.extent)
        }
        return mask
    }

    // MARK: masks

    static func lipMask(_ face: FaceInfo, size: CGSize) -> CIImage? {
        let outer = FaceReshape.points(face, "outerLips"), inner = FaceReshape.points(face, "innerLips")
        guard outer.count >= 3, size.width > 0, size.height > 0 else { return nil }
        return polygons(size: size) { fill in
            fill(outer, 1)
            if inner.count >= 3 { fill(inner, 0) }        // the open mouth is not lipstick
        }
    }

    static func blushMask(_ face: FaceInfo, style: MakeupParams.BlushStyle, size: CGSize) -> CIImage? {
        let spots = blushSpots(face, style: style)
        guard !spots.isEmpty, size.width > 0, size.height > 0 else { return nil }
        var mask = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        for s in spots {
            let r = s.radius * Double(size.width)
            let g = CIFilter.radialGradient()
            g.center = CGPoint(x: s.center.x * size.width, y: (1 - s.center.y) * size.height)
            g.radius0 = Float(r * 0.15); g.radius1 = Float(r); g.color0 = .white; g.color1 = .black
            guard var spot = g.outputImage?.cropped(to: CGRect(origin: .zero, size: size)) else { continue }
            if s.squash != 1 {      // squash vertically about the spot center
                let cy = g.center.y
                spot = spot.transformed(by: CGAffineTransform(translationX: 0, y: -cy).scaledBy(x: 1, y: 1 / s.squash).translatedBy(x: 0, y: 0))
                    .transformed(by: CGAffineTransform(translationX: 0, y: cy))
            }
            mask = spot.cropped(to: mask.extent).applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: mask.extent)
        }
        return mask
    }

    private static func polygons(size: CGSize, _ draw: (_ fill: ([CGPoint], CGFloat) -> Void) -> Void) -> CIImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        draw { pts, gray in
            ctx.setFillColor(gray: gray, alpha: 1)
            ctx.addLines(between: pts.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }); ctx.closePath(); ctx.fillPath()
        }
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    // MARK: render

    static func apply(_ p: MakeupParams, to image: CIImage, face: FaceInfo) -> CIImage {
        guard !p.isIdentity else { return image }
        var out = image
        let size = image.extent.size
        func solid(_ c: RGBA) -> CIImage { CIImage(color: CIColor(red: c.r, green: c.g, blue: c.b)).cropped(to: image.extent) }
        func scaled(_ mask: CIImage, _ k: Double) -> CIImage {
            mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)])
        }
        func tint(_ color: RGBA, mask: CIImage, opacity: Double, mode: String) -> CIImage {
            let blended = solid(color).applyingFilter(mode, parameters: [kCIInputBackgroundImageKey: out]).cropped(to: image.extent)
            let m = CIFilter.blendWithMask(); m.inputImage = blended; m.backgroundImage = out; m.maskImage = scaled(mask, min(max(opacity, 0), 1))
            return m.outputImage?.cropped(to: image.extent) ?? out
        }

        if p.lipOpacity > 0, var lips = lipMask(face, size: size) {
            lips = lips.clampedToExtent().applyingGaussianBlur(sigma: Double(size.width) * 0.002).cropped(to: lips.extent)
            let mode = p.lipFinish == .matte ? "CIMultiplyBlendMode" : "CISoftLightBlendMode"
            var m = lips
            if p.ombre > 0 {     // fade toward the lip center: inner erode via blur then subtract a share
                let center = lips.clampedToExtent().applyingGaussianBlur(sigma: Double(size.width) * 0.012).cropped(to: lips.extent)
                m = center.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: lips])
                m = lips.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1 - p.ombre, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1 - p.ombre, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1 - p.ombre, w: 0)])
                    .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: scaled(m, p.ombre)]).cropped(to: lips.extent)
                m = m.applyingFilter("CIColorClamp")
            }
            out = tint(p.lipColor, mask: m, opacity: p.lipOpacity, mode: mode)
            if p.lipFinish == .gloss {
                out = tint(RGBA.white, mask: lips.clampedToExtent().applyingGaussianBlur(sigma: Double(size.width) * 0.01).cropped(to: lips.extent), opacity: 0.18, mode: "CISoftLightBlendMode")
            }
        }
        if p.foundation > 0, let skin = SkinMask.make(face: face, size: size, feather: 0.03) {
            // pull the face toward its own average color and soften, which evens out patches and redness
            let avg = out.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: MakeupRenderer.ciRect(MakeupRenderer.faceBox(face), size: size))])
            var px = [UInt8](repeating: 0, count: 4)
            CIContext().render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            let tone = RGBA(r: Double(px[0]) / 255, g: Double(px[1]) / 255, b: Double(px[2]) / 255, a: 1)
            out = tint(tone, mask: skin, opacity: p.foundation * 0.6, mode: "CIColorBlendMode")   // tone of the face average, light and texture of the photo
        }
        if p.contour > 0, let m = MakeupRenderer.spotsMask(contourSpots(face), size: size) {
            out = tint(RGBA(r: 0.45, g: 0.3, b: 0.25, a: 1), mask: m, opacity: p.contour * 0.7, mode: "CIMultiplyBlendMode")
        }
        if p.highlight > 0, let m = MakeupRenderer.spotsMask(highlightSpots(face), size: size) {
            out = tint(RGBA.white, mask: m, opacity: min(p.highlight * 1.2, 1), mode: "CISoftLightBlendMode")
        }
        if p.blushOpacity > 0, let blush = blushMask(face, style: p.blushStyle, size: size) {
            out = tint(p.blushColor, mask: blush, opacity: p.blushOpacity, mode: "CISoftLightBlendMode")
        }
        return out
    }
}
