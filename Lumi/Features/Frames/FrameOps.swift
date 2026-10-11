import CoreImage
import CoreImage.CIFilterBuiltins

struct FrameConfig: Codable, Equatable {
    enum Style: String, Codable, CaseIterable { case inner, outer, simple, poster }
    var style = Style.outer
    var padding = 0.04              // fraction of the short side, 0...0.25
    var color = RGBA.white
    var cornerRadius = 0.0          // fraction of the short side, inner frames only

    var isIdentity: Bool { padding <= 0 }
}

enum FrameOps {
    /// Canvas size after the frame. Outer/poster add space; inner and simple keep the photo's size.
    static func outputSize(_ c: FrameConfig, for size: CGSize) -> CGSize {
        guard !c.isIdentity else { return size }
        let pad = (min(size.width, size.height) * min(max(c.padding, 0), 0.25)).rounded()
        switch c.style {
        case .inner, .simple: return size
        case .outer: return CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
        case .poster: return CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad + pad * 2.5)    // wider bottom margin
        }
    }

    static func apply(_ c: FrameConfig, to image: CIImage) -> CIImage {
        guard !c.isIdentity else { return image }
        let e = image.extent
        let pad = (min(e.width, e.height) * min(max(c.padding, 0), 0.25)).rounded()
        let color = CIColor(red: c.color.r, green: c.color.g, blue: c.color.b, alpha: c.color.a)
        let base = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        switch c.style {
        case .outer, .poster:
            let bottom = c.style == .poster ? pad * 3.5 : pad
            let canvas = CGRect(x: 0, y: 0, width: e.width + 2 * pad, height: e.height + pad + bottom)
            return base.transformed(by: CGAffineTransform(translationX: pad, y: bottom)).composited(over: CIImage(color: color).cropped(to: canvas)).cropped(to: canvas)
        case .inner:
            return border(over: base, thickness: pad, color: color, radius: min(e.width, e.height) * c.cornerRadius)
        case .simple:
            // a thin line inset from the edge, photo untouched elsewhere
            return border(over: base, thickness: max(2, pad * 0.15), color: color, radius: 0, inset: pad)
        }
    }

    /// Draws a frame ring (outer rect minus inner rect) of `thickness` on top of the image.
    private static func border(over base: CIImage, thickness: CGFloat, color: CIColor, radius: CGFloat, inset: CGFloat = 0) -> CIImage {
        let e = base.extent
        let outer = e.insetBy(dx: inset, dy: inset), inner = outer.insetBy(dx: thickness, dy: thickness)
        guard inner.width > 0, inner.height > 0 else { return CIImage(color: color).cropped(to: e) }
        let w = Int(e.width), h = Int(e.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return base }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: max(radius - thickness, 0), cornerHeight: max(radius - thickness, 0), transform: nil))
        ctx.fillPath(using: .evenOdd)
        guard let cg = ctx.makeImage() else { return base }
        let mask = CIImage(cgImage: cg)
        let f = CIFilter.blendWithMask(); f.inputImage = CIImage(color: color).cropped(to: e); f.backgroundImage = base; f.maskImage = mask
        return f.outputImage?.cropped(to: e) ?? base
    }
}
