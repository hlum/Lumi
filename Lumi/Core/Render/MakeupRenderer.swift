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
    var isIdentity: Bool { lipOpacity == 0 && blushOpacity == 0 }
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
    static func faceBox(_ face: FaceInfo) -> CGRect {
        CGRect(x: face.box.minX, y: 1 - face.box.maxY, width: face.box.width, height: face.box.height)
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
        if p.blushOpacity > 0, let blush = blushMask(face, style: p.blushStyle, size: size) {
            out = tint(p.blushColor, mask: blush, opacity: p.blushOpacity, mode: "CISoftLightBlendMode")
        }
        return out
    }
}
