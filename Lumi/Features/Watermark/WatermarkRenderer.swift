import CoreImage
import Foundation

enum WatermarkRenderer {
    /// Draws a text watermark (single or tiled). Image watermarks go through the sticker/layer path.
    static func apply(_ w: Watermark, to image: CIImage, date: Date = .now) -> CIImage {
        guard case .text(let text) = w.kind, !text.isEmpty else { return image }
        var style = TextStyle(); style.size = w.size; style.color = RGBA(r: 1, g: 1, b: 1, a: 1); style.shadowRadius = 0.15
        guard let mark = LayerRenderer.textImage(text, style: style, imageHeight: image.extent.height) else { return image }
        let e = image.extent
        let aspect = Double(e.width / e.height), markAspect = Double(mark.extent.width / mark.extent.height)
        if w.isTiled {
            let centers = WatermarkMath.tileCenters(imageAspect: aspect, markAspect: markAspect, size: w.size, spacing: w.tileSpacing)
            return centers.reduce(image) { acc, c in
                LayerRenderer.composite(mark, transform: LayerTransform(center: c, scale: 1, rotation: w.tileAngle), opacity: w.opacity, over: acc)
            }
        }
        // single mark: bottom-right corner with a margin
        return LayerRenderer.composite(mark, transform: LayerTransform(center: CGPoint(x: 1 - 0.04 - (markAspect * w.size / aspect) / 2, y: 0.94), scale: 1, rotation: 0), opacity: w.opacity, over: image)
    }
}
