import CoreImage
import CoreML
import Foundation

/// Removes the masked area of an image. Fakeable in tests.
protocol Inpainting {
    func inpaint(_ image: CIImage, mask: CIImage) throws -> CIImage
}

enum InpaintPlan {
    static let modelSide = 800

    /// Crop (in pixels) around the mask with context, so big photos are processed in a window, not downsampled whole.
    /// `maskBounds` and the result are in the same pixel space as `imageSize`. Nil when the mask is empty.
    static func cropRect(maskBounds: CGRect, imageSize: CGSize, context: CGFloat = 1.0, minSide: CGFloat = 256) -> CGRect? {
        guard !maskBounds.isNull, !maskBounds.isEmpty, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: imageSize)
        let side = max(max(maskBounds.width, maskBounds.height) * (1 + 2 * context), minSide)
        var r = CGRect(x: maskBounds.midX - side / 2, y: maskBounds.midY - side / 2, width: side, height: side)
        // slide the square back inside the image instead of shrinking it, then clamp if the image is smaller than the square
        if r.minX < 0 { r.origin.x = 0 }; if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.width }; if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.height }
        return r.intersection(bounds).integral.intersection(bounds)
    }

    /// Tight bounds of the nonzero pixels of an 8-bit mask, in pixels with a bottom-left origin (Core Image).
    static func bounds(ofMask pixels: [UInt8], width: Int, height: Int, threshold: UInt8 = 8) -> CGRect {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height { for x in 0..<width where pixels[y * width + x] > threshold {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return .null }
        // buffer row 0 is the top; flip to bottom-left origin
        return CGRect(x: minX, y: height - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

/// Loads LaMa on first use so app launch isn't slowed by a ~200 MB model.
final class LazyInpainter: Inpainting {
    private var real: LaMaInpainter?
    private var revision = -1
    func inpaint(_ image: CIImage, mask: CIImage) throws -> CIImage {
        if real == nil || revision != ModelStore.shared.revision { real = try LaMaInpainter(); revision = ModelStore.shared.revision }   // a swapped model is picked up here
        return try real!.inpaint(image, mask: mask)
    }
}

enum InpaintError: Error, Equatable { case modelMissing, emptyMask, bufferFailed, predictionFailed }

/// LaMa (Apache-2.0) on Core ML. Runs on a window around the mask and blends the result back at full resolution.
final class LaMaInpainter: Inpainting {
    private let model: MLModel
    private let entry: ModelEntry
    private let context = CIContext()

    static var isModelAvailable: Bool { ModelStore.shared.isAvailable(.inpaint) }

    /// Loads whichever model is active for object removal (the bundled LaMa unless the user swapped it).
    init(store: ModelStore = .shared) throws {
        do { (model, entry) = try store.load(.inpaint) } catch { throw InpaintError.modelMissing }
    }

    private var modelSide: Int { entry.side ?? InpaintPlan.modelSide }

    func inpaint(_ image: CIImage, mask: CIImage) throws -> CIImage {
        let extent = image.extent
        let w = Int(extent.width), h = Int(extent.height)
        var maskPixels = [UInt8](repeating: 0, count: w * h)
        context.render(mask.cropped(to: extent), toBitmap: &maskPixels, rowBytes: w, bounds: extent, format: .L8, colorSpace: nil)
        let mb = InpaintPlan.bounds(ofMask: maskPixels, width: w, height: h)
        guard let crop = InpaintPlan.cropRect(maskBounds: mb, imageSize: extent.size) else { throw InpaintError.emptyMask }

        let side = CGFloat(modelSide)
        func window(_ img: CIImage) -> CIImage {
            let c = img.cropped(to: crop.offsetBy(dx: extent.minX, dy: extent.minY))
            return c.transformed(by: CGAffineTransform(translationX: -c.extent.minX, y: -c.extent.minY)
                .scaledBy(x: side / crop.width, y: side / crop.height))
        }
        let imgBuf = try buffer(window(image), format: kCVPixelFormatType_32BGRA)
        // binarize the mask: LaMa wants 0/1
        let binary = window(mask).applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0), "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)])
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 40, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 40, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 40, w: 0)])
            .applyingFilter("CIColorClamp")
        let maskBuf = try buffer(binary, format: kCVPixelFormatType_OneComponent8)

        let inputs = try MLDictionaryFeatureProvider(dictionary: [entry.io["image"] ?? "image": MLFeatureValue(pixelBuffer: imgBuf), entry.io["mask"] ?? "mask": MLFeatureValue(pixelBuffer: maskBuf)])
        guard let out = try model.prediction(from: inputs).featureValue(for: entry.io["output"] ?? "output")?.imageBufferValue else { throw InpaintError.predictionFailed }

        // scale the result back to the crop size and blend only where the (slightly grown) mask is set
        let result = CIImage(cvPixelBuffer: out).transformed(by: CGAffineTransform(scaleX: crop.width / side, y: crop.height / side))
            .transformed(by: CGAffineTransform(translationX: crop.minX + extent.minX, y: crop.minY + extent.minY))
        let grown = mask.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 3])
            .applyingGaussianBlur(sigma: 1.5).cropped(to: extent)
        let blend = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: result.cropped(to: extent), kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: grown])!
        return blend.outputImage!.cropped(to: extent)
    }

    private func buffer(_ img: CIImage, format: OSType) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let n = modelSide
        guard CVPixelBufferCreate(nil, n, n, format, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb) == kCVReturnSuccess, let pb else { throw InpaintError.bufferFailed }
        context.render(img, to: pb, bounds: CGRect(x: 0, y: 0, width: n, height: n), colorSpace: format == kCVPixelFormatType_OneComponent8 ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB))
        return pb
    }
}
