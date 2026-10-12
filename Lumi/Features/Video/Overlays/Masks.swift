import CoreGraphics
import CoreImage
import UIKit

/// Shape masks for overlays: the picture keeps only what is inside the shape (alpha).
enum Masks {
    static func apply(_ shape: PiP.Shape, to image: CIImage) -> CIImage {
        guard shape != .rect else { return image }
        let e = image.extent
        let w = Int(e.width), h = Int(e.height)
        guard w > 1, h > 1, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return image }
        let r = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(gray: 1, alpha: 1)
        switch shape {
        case .rect: break
        case .rounded: ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(r.width, r.height) * 0.12, cornerHeight: min(r.width, r.height) * 0.12, transform: nil)); ctx.fillPath()
        case .circle: ctx.fillEllipse(in: CGRect(x: (r.width - min(r.width, r.height)) / 2, y: (r.height - min(r.width, r.height)) / 2, width: min(r.width, r.height), height: min(r.width, r.height)))
        case .heart:
            if let p = StickerLibrary.path("heart")?.copy() as? UIBezierPath {
                p.apply(CGAffineTransform(scaleX: r.width, y: r.height)); p.apply(CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -r.height))
                ctx.addPath(p.cgPath); ctx.fillPath()
            }
        }
        guard let cg = ctx.makeImage() else { return image }
        let mask = CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY))
        let f = CIFilter.blendWithMask()
        f.inputImage = image; f.maskImage = mask; f.backgroundImage = CIImage(color: .clear).cropped(to: e)
        return f.outputImage?.cropped(to: e) ?? image
    }
}
