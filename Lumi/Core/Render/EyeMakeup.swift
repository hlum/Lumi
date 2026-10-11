import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

struct EyeSide: Codable, Equatable {
    var shadowColor = RGBA(r: 0.6, g: 0.4, b: 0.5, a: 1)
    var shadow = 0.0            // 0...1
    var liner = 0.0             // 0...1 thickness and strength
    var lashes = 0.0            // 0...1
    var isIdentity: Bool { shadow == 0 && liner == 0 && lashes == 0 }
}

struct EyeMakeup: Codable, Equatable {
    enum BrowShape: String, Codable, CaseIterable { case natural, straight, arched, soft }
    var left = EyeSide()
    var right = EyeSide()
    var browColor = RGBA(r: 0.25, g: 0.15, b: 0.1, a: 1)
    var browOpacity = 0.0       // 0...1
    var browShape = BrowShape.natural
    var browHeight = 0.0        // -1...1 lift or lower

    var isIdentity: Bool { left.isIdentity && right.isIdentity && browOpacity == 0 && browShape == .natural && browHeight == 0 }

    /// Both eyes the same.
    mutating func setBoth(_ change: (inout EyeSide) -> Void) { change(&left); change(&right) }
}

enum EyeMakeupRenderer {
    private static func draw(size: CGSize, _ body: (CGContext, (CGPoint) -> CGPoint) -> Void) -> CIImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        body(ctx) { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    /// The upper lid line of an eye: its upper half, left to right (image-normalized, y-down).
    static func upperLid(_ eye: [CGPoint]) -> [CGPoint] {
        guard let c = FaceReshape.center(eye) else { return [] }
        return eye.filter { $0.y <= c.y + 0.0005 }.sorted { $0.x < $1.x }
    }

    static func shadowMask(_ eye: [CGPoint], size: CGSize) -> CIImage? {
        let lid = upperLid(eye)
        let w = FaceReshape.width(eye)
        guard lid.count >= 2, w > 0 else { return nil }
        // a band that follows the upper lid and rises about half an eye-width above it
        let band = lid + lid.reversed().map { CGPoint(x: $0.x, y: $0.y - w * 0.5) }
        let m = draw(size: size) { ctx, px in
            ctx.setFillColor(gray: 1, alpha: 1); ctx.addLines(between: band.map(px)); ctx.closePath(); ctx.fillPath()
            // the eyeball itself stays clear
            ctx.setFillColor(gray: 0, alpha: 1); ctx.addLines(between: eye.map(px)); ctx.closePath(); ctx.fillPath()
        }
        return m?.clampedToExtent().applyingGaussianBlur(sigma: Double(size.width) * 0.004).cropped(to: m!.extent)
    }

    static func linerMask(_ eye: [CGPoint], size: CGSize, thickness: Double, wing: Bool) -> CIImage? {
        var lid = upperLid(eye)
        guard lid.count >= 2, let c = FaceReshape.center(eye) else { return nil }
        let w = FaceReshape.width(eye)
        if wing, let last = lid.last { lid.append(CGPoint(x: last.x + (last.x < c.x ? -1 : 1) * w * 0.25, y: last.y - w * 0.12)) }
        let width = max(1, CGFloat(w * Double(size.width)) * CGFloat(0.04 + thickness * 0.1))
        return draw(size: size) { ctx, px in
            ctx.setStrokeColor(gray: 1, alpha: 1); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.addLines(between: lid.map(px)); ctx.strokePath()
        }
    }

    static func browMask(_ brow: [CGPoint], size: CGSize) -> CIImage? {
        guard brow.count >= 3 else { return nil }
        let m = draw(size: size) { ctx, px in ctx.setFillColor(gray: 1, alpha: 1); ctx.addLines(between: brow.map(px)); ctx.closePath(); ctx.fillPath() }
        return m?.clampedToExtent().applyingGaussianBlur(sigma: Double(size.width) * 0.002).cropped(to: m!.extent)
    }

    /// Reshape strokes for brow shape and height. Brow points here are image-normalized, y-down.
    static func browStrokes(_ face: FaceInfo, shape: EyeMakeup.BrowShape, height: Double) -> [BrushStroke] {
        var out: [BrushStroke] = []
        for region in ["leftEyebrow", "rightEyebrow"] {
            let pts = FaceReshape.points(face, region)
            guard pts.count >= 3, let c = FaceReshape.center(pts) else { continue }
            let w = Float(FaceReshape.width(pts))
            let sorted = pts.sorted { $0.x < $1.x }
            func s(_ p: CGPoint, dy: Float, r: Float = 0.5) -> BrushStroke { BrushStroke(kind: .push, x: Float(p.x), y: Float(p.y), radius: w * r, strength: 1, dirX: 0, dirY: dy) }
            switch shape {
            case .natural: break
            case .arched: out.append(s(CGPoint(x: c.x + (sorted.last!.x - c.x) * 0.2, y: c.y), dy: -w * 0.12))                       // peak up
            case .straight: out.append(s(CGPoint(x: c.x, y: c.y), dy: w * 0.06, r: 0.45))                                          // flatten the peak
            case .soft: out.append(s(sorted.first!, dy: -w * 0.04, r: 0.4)); out.append(s(sorted.last!, dy: w * 0.04, r: 0.4))    // gentle downward slope
            }
            if height != 0 { out.append(s(c, dy: -Float(height) * w * 0.15, r: 0.9)) }
        }
        return out
    }

    private static func paint(_ color: RGBA, over image: CIImage, mask: CIImage, opacity: Double, mode: String) -> CIImage {
        let e = image.extent
        let solid = CIImage(color: CIColor(red: color.r, green: color.g, blue: color.b)).cropped(to: e)
        let blended = solid.applyingFilter(mode, parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
        let k = CGFloat(min(max(opacity, 0), 1))
        let m = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)])
        let f = CIFilter.blendWithMask(); f.inputImage = blended; f.backgroundImage = image; f.maskImage = m
        return f.outputImage?.cropped(to: e) ?? image
    }

    /// Paints shadow, liner, lashes and brow color. (Brow shape and height are warp strokes: see `browStrokes`.)
    static func apply(_ m: EyeMakeup, to image: CIImage, face: FaceInfo) -> CIImage {
        guard !m.isIdentity else { return image }
        let size = image.extent.size
        var out = image
        for (region, side) in [("leftEye", m.left), ("rightEye", m.right)] where !side.isIdentity {
            let eye = FaceReshape.points(face, region)
            guard eye.count >= 3 else { continue }
            if side.shadow > 0, let mask = shadowMask(eye, size: size) { out = paint(side.shadowColor, over: out, mask: mask, opacity: side.shadow * 0.8, mode: "CIMultiplyBlendMode") }
            if side.liner > 0, let mask = linerMask(eye, size: size, thickness: side.liner, wing: false) { out = paint(RGBA(r: 0.05, g: 0.03, b: 0.03, a: 1), over: out, mask: mask, opacity: min(side.liner * 1.4, 1), mode: "CISourceOverCompositing") }
            if side.lashes > 0, let mask = linerMask(eye, size: size, thickness: 0.4 + side.lashes * 0.6, wing: true) { out = paint(RGBA(r: 0.02, g: 0.02, b: 0.02, a: 1), over: out, mask: mask, opacity: side.lashes, mode: "CISourceOverCompositing") }
        }
        if m.browOpacity > 0 {
            for region in ["leftEyebrow", "rightEyebrow"] {
                if let mask = browMask(FaceReshape.points(face, region), size: size) { out = paint(m.browColor, over: out, mask: mask, opacity: m.browOpacity, mode: "CISoftLightBlendMode") }
            }
        }
        return out
    }
}
