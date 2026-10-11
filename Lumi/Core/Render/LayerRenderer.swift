import CoreImage
import UIKit

enum LayerRenderer {
    /// Renders a text layer's glyphs at `imageHeight`, unrotated. Size scales with image height, so
    /// preview (proxy) and export (full-res) are the same picture at different resolutions.
    static func textImage(_ text: String, style: TextStyle, imageHeight: CGFloat) -> CIImage? {
        let pt = max(1, CGFloat(style.size) * imageHeight)
        let font = UIFont(name: style.fontName, size: pt) ?? .boldSystemFont(ofSize: pt)
        let para = NSMutableParagraphStyle()
        para.alignment = style.alignment == .left ? .left : style.alignment == .right ? .right : .center
        func ui(_ c: RGBA) -> UIColor { UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ui(style.color), .paragraphStyle: para]
        if style.strokeWidth > 0 {
            attrs[.strokeColor] = ui(style.strokeColor)
            attrs[.strokeWidth] = -style.strokeWidth * 100        // negative: stroke and fill
        }
        let shadowPad = CGFloat(style.shadowRadius) * pt
        if style.shadowRadius > 0 {
            let sh = NSShadow(); sh.shadowBlurRadius = shadowPad; sh.shadowColor = UIColor.black.withAlphaComponent(0.6)
            sh.shadowOffset = CGSize(width: 0, height: shadowPad / 2)
            attrs[.shadow] = sh
        }
        let str = NSAttributedString(string: text, attributes: attrs)
        let bound = str.boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin], context: nil)
        let pad = ceil(shadowPad * 2 + pt * CGFloat(style.strokeWidth) + 2)
        let size = CGSize(width: ceil(bound.width) + pad * 2, height: ceil(bound.height) + pad * 2)
        guard size.width > 0, size.height > 0, size.width < 16_384, size.height < 16_384 else { return nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            str.draw(with: CGRect(x: pad, y: pad, width: ceil(bound.width), height: ceil(bound.height)), options: [.usesLineFragmentOrigin], context: nil)
        }
        return CIImage(image: img)
    }

    /// Places a layer image over `base` using the layer's normalized transform.
    static func composite(_ layerImage: CIImage, transform t: LayerTransform, opacity: Double, over base: CIImage) -> CIImage {
        let e = base.extent
        var img = layerImage.transformed(by: CGAffineTransform(translationX: -layerImage.extent.midX, y: -layerImage.extent.midY))
        if t.flipH { img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1)) }
        img = img.transformed(by: CGAffineTransform(scaleX: t.scale, y: t.scale))
        img = img.transformed(by: CGAffineTransform(rotationAngle: -t.rotation))      // clockwise on screen
        let cx = e.minX + t.center.x * e.width, cy = e.minY + (1 - t.center.y) * e.height
        img = img.transformed(by: CGAffineTransform(translationX: cx, y: cy))
        if opacity < 1 {
            img = img.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: min(max(opacity, 0), 1))])
        }
        return img.composited(over: base).cropped(to: e)
    }

    static func render(_ stack: LayerStack, over base: CIImage, stickerImage: (String) -> CIImage? = { StickerLibrary.image($0) }) -> CIImage {
        stack.layers.reduce(base) { acc, layer in
            switch layer.content {
            case .text(let s, let style):
                guard let ti = textImage(s, style: style, imageHeight: base.extent.height) else { return acc }
                return composite(ti, transform: layer.transform, opacity: layer.opacity, over: acc)
            case .sticker(let id, let outline):
                guard var si = stickerImage(id) else { return acc }
                if outline > 0 { si = OutlineOps.apply(to: si, width: outline) }
                // sticker size is relative to the photo's short side, like text is relative to height
                let scale = min(base.extent.width, base.extent.height) * 0.3 / max(si.extent.width, 1)
                si = si.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                return composite(si, transform: layer.transform, opacity: layer.opacity, over: acc)
            }
        }
    }
}
