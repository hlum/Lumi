import CoreImage
import Foundation

/// One-tap restoration for old photos: tidy tone, optionally colorize a black-and-white scan, and scale it up if it is small.
enum OldPhotoRestore {
    /// True when the picture has almost no color (a black-and-white or sepia-free scan). Looks at a 32x32 thumbnail.
    static func isMostlyGray(_ image: CIImage, threshold: Double = 0.04) -> Bool {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return false }
        let n = 32
        let thumb = image.transformed(by: CGAffineTransform(scaleX: CGFloat(n) / e.width, y: CGFloat(n) / e.height).translatedBy(x: -e.minX, y: -e.minY))
        var px = [UInt8](repeating: 0, count: n * n * 4)
        CIContext().render(thumb, toBitmap: &px, rowBytes: n * 4, bounds: CGRect(x: 0, y: 0, width: n, height: n), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var total = 0.0
        for i in 0..<(n * n) {
            let r = Double(px[i * 4]), g = Double(px[i * 4 + 1]), b = Double(px[i * 4 + 2])
            total += (abs(r - g) + abs(g - b) + abs(r - b)) / (3 * 255)
        }
        return total / Double(n * n) < threshold
    }

    struct Plan: Equatable { var adjust: AdjustParams; var upscale: Int?; var colorize: Double? }

    /// Chooses steps from the photo itself. `canUpscale`/`canColorize` say whether the models are available.
    static func plan(for image: CIImage, canUpscale: Bool, canColorize: Bool) -> Plan {
        var adjust = AdjustParams(); adjust.contrast = 0.15; adjust.shadows = 0.2; adjust.highlights = -0.15; adjust.sharpen = 0.3
        let long = max(image.extent.width, image.extent.height)
        let up: Int? = canUpscale && long <= CGFloat(RealESRGANUpscaler.maxInputSide) / 4 ? 4 : (canUpscale && long <= CGFloat(RealESRGANUpscaler.maxInputSide) / 2 ? 2 : nil)
        return Plan(adjust: adjust, upscale: up, colorize: canColorize && isMostlyGray(image) ? 1 : nil)
    }

    static func apply(_ plan: Plan, to doc: EditDocument) -> EditDocument {
        var d = doc
        d.adjust = plan.adjust
        // colorize before upscaling: the colorizer works at 512 px and is cheaper on the original size
        d.colorize = plan.colorize
        d.upscale = plan.upscale
        return d
    }
}
