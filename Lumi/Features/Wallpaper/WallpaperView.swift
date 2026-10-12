import CoreGraphics
import CoreImage

/// Crops a photo to a screen shape (aspect-fill, then zoom and pan) at the screen's pixel size.
enum WallpaperMaker {
    struct Target: Equatable { var name: String; var width: Int; var height: Int; var aspect: Double { Double(width) / Double(height) } }
    static let targets: [Target] = [
        .init(name: "iPhone", width: 1290, height: 2796), .init(name: "iPhone mini", width: 1080, height: 2340),
        .init(name: "iPad", width: 2048, height: 2732), .init(name: "Lock screen", width: 1206, height: 2622),
    ]

    static func make(_ image: CIImage, target: Target, zoom: Double = 1, pan: CGPoint = .zero) -> CIImage {
        let e = image.extent
        let crop = CollageMath.sourceCrop(image: e.size, slotAspect: target.aspect, zoom: zoom, pan: pan)
        guard crop.width > 0 else { return image }
        let ci = CGRect(x: e.minX + crop.minX, y: e.minY + e.height - crop.maxY, width: crop.width, height: crop.height)
        let s = CGFloat(target.width) / ci.width
        return image.cropped(to: ci).transformed(by: CGAffineTransform(scaleX: s, y: s).translatedBy(x: -ci.minX, y: -ci.minY))
            .cropped(to: CGRect(x: 0, y: 0, width: target.width, height: target.height))
    }
}
