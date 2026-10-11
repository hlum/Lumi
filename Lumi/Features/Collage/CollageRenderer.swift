import UIKit
import CoreGraphics
import CoreImage

enum CollageRenderer {
    /// Draws `photos` into the layout's slots on a canvas `width` px wide.
    static func render(_ state: CollageState, photos: [CIImage], width: Int, background: RGBA = .white) -> CIImage {
        let layout = state.layout
        let w = CGFloat(max(width, 16)), h = (w / CGFloat(layout.aspect)).rounded()
        let canvas = CGRect(x: 0, y: 0, width: w, height: h)
        var out = CIImage(color: CIColor(red: background.r, green: background.g, blue: background.b)).cropped(to: canvas)
        guard !photos.isEmpty else { return out }
        let inset = CGFloat(state.border) * w                                // extra gap inside each slot

        for (i, slot) in layout.slots.enumerated() where i < state.fills.count {
            let fill = state.fills[i]
            guard photos.indices.contains(fill.photo) else { continue }
            // slot rect in canvas px (CI is bottom-left, layouts are top-left)
            let r = CGRect(x: slot.rect.minX * w, y: (1 - slot.rect.maxY) * h, width: slot.rect.width * w, height: slot.rect.height * h).insetBy(dx: inset, dy: inset)
            guard r.width > 1, r.height > 1 else { continue }
            let photo = photos[fill.photo], pe = photo.extent
            // source crop is top-left based; convert to CI
            let crop = CollageMath.sourceCrop(image: pe.size, slotAspect: Double(r.width / r.height), zoom: fill.zoom, pan: fill.pan)
            let ciCrop = CGRect(x: pe.minX + crop.minX, y: pe.minY + pe.height - crop.maxY, width: crop.width, height: crop.height)
            let s = max(r.width / ciCrop.width, r.height / ciCrop.height)
            let fitted = photo.cropped(to: ciCrop).transformed(by: CGAffineTransform(scaleX: s, y: s).translatedBy(x: -ciCrop.minX, y: -ciCrop.minY))
                .transformed(by: CGAffineTransform(translationX: r.minX, y: r.minY)).cropped(to: r)
            let mask = slotMask(slot.shape, in: r, canvas: canvas, cornerRadius: CGFloat(state.cornerRadius) * min(r.width, r.height))
            let blend = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: fitted, kCIInputBackgroundImageKey: out, kCIInputMaskImageKey: mask])!
            out = blend.outputImage?.cropped(to: canvas) ?? out
        }
        return out
    }

    /// White inside the slot's shape, black elsewhere, covering the whole canvas.
    static func slotMask(_ shape: CollageLayout.Shape, in r: CGRect, canvas: CGRect, cornerRadius: CGFloat) -> CIImage {
        let cw = Int(canvas.width), ch = Int(canvas.height)
        guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return CIImage(color: .white).cropped(to: canvas) }
        ctx.setFillColor(gray: 1, alpha: 1)
        switch shape {
        case .rect: ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(cornerRadius, r.width / 2), cornerHeight: min(cornerRadius, r.height / 2), transform: nil))
        case .circle: ctx.addEllipse(in: r)
        case .triangle:
            ctx.move(to: CGPoint(x: r.midX, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.minX, y: r.minY)); ctx.closePath()
        case .heart:
            let p = StickerLibrary.path("heart")!.copy() as! UIBezierPath
            p.apply(CGAffineTransform(scaleX: r.width, y: r.height)); p.apply(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -r.height))   // y-down path into y-up context
            p.apply(CGAffineTransform(translationX: r.minX, y: r.minY)); ctx.addPath(p.cgPath)
        }
        ctx.fillPath()
        return ctx.makeImage().map { CIImage(cgImage: $0) } ?? CIImage(color: .white).cropped(to: canvas)
    }
}
