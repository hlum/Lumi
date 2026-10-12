import CoreImage
import CoreML

/// Pixel-accurate face parts from the bundled BiSeNet face-parsing model (CelebAMask-HQ classes), one window per face.
enum FacePart: Int, CaseIterable {
    case background = 0, skin, leftBrow, rightBrow, leftEye, rightEye, glasses, leftEar, rightEar, earring, nose, mouth, upperLip, lowerLip, neck, necklace, cloth, hair, hat
}

struct FaceParse {
    /// Class per pixel of the window, row 0 at the top.
    let labels: [UInt8]
    let side: Int
    /// The window in the photo, in Core Image pixels (y-up).
    let window: CGRect

    /// A soft 0...1 mask of `parts`, placed in the photo's coordinates and cropped to `extent`.
    func mask(_ parts: Set<FacePart>, extent: CGRect, soften: Double = 1.0) -> CIImage {
        let raw = parts.map { UInt8($0.rawValue) }
        let bytes = labels.map { raw.contains($0) ? UInt8(255) : 0 }
        guard let small = MaskModelOutput.image(bytes, width: side, height: side) else { return CIImage(color: .black).cropped(to: extent) }
        let soft = soften > 0 ? small.clampedToExtent().applyingGaussianBlur(sigma: soften).cropped(to: small.extent) : small
        let placed = soft.transformed(by: CGAffineTransform(scaleX: window.width / CGFloat(side), y: window.height / CGFloat(side)))
            .transformed(by: CGAffineTransform(translationX: window.minX, y: window.minY))
        return placed.composited(over: CIImage(color: .black).cropped(to: extent)).cropped(to: extent)
    }

    /// Share of the window labelled with `part`.
    func fraction(_ part: FacePart) -> Double { Double(labels.filter { $0 == UInt8(part.rawValue) }.count) / Double(max(labels.count, 1)) }
}

/// Runs the face-parsing model in the `faceParsing` slot (falls back to the hair slot's face-parsing model).
struct FaceParser {
    var store: ModelStore = .shared

    /// The square window around a Vision face box (normalized, y-up) that the model sees: the whole head with a margin.
    static func window(forFace box: CGRect, in extent: CGRect) -> CGRect {
        let w = box.width * extent.width, h = box.height * extent.height, side = max(w, h) * 1.9
        let cx = extent.minX + box.midX * extent.width, cy = extent.minY + box.midY * extent.height + side * 0.06
        return CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
    }

    func parse(_ image: CIImage, faceBox: CGRect) throws -> FaceParse {
        let (model, entry) = try store.isAvailable(.faceParsing) ? store.load(.faceParsing) : store.load(.hairSegmentation)
        let side = entry.side ?? 512, window = Self.window(forFace: faceBox, in: image.extent)
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb) == kCVReturnSuccess, let pb else { throw InpaintError.bufferFailed }
        let crop = image.clampedToExtent().cropped(to: window).transformed(by: CGAffineTransform(translationX: -window.minX, y: -window.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(side) / window.width, y: CGFloat(side) / window.height))
        CIContext().render(crop, to: pb, bounds: CGRect(x: 0, y: 0, width: side, height: side), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [entry.io["input"] ?? "input": MLFeatureValue(pixelBuffer: pb)]))
        guard let arr = out.featureValue(for: entry.io["output"] ?? "output")?.multiArrayValue,
              let p = MaskDecode.extract(MaskModelOutput.floats(arr), shape: arr.shape.map(\.intValue)) else { throw InpaintError.predictionFailed }
        return FaceParse(labels: p.plane.map { UInt8(min(max($0.rounded(), 0), 255)) }, side: p.width, window: window)
    }
}
