import CoreImage
import CoreML

/// Output of a segmentation model as a mask: probabilities, or raw scores that are squashed first.
enum MaskDecode {
    /// `values` is a flat h x w plane. Values outside 0...1 are treated as logits; a plane that is already 0...1 is used as is.
    static func plane(_ values: [Float], looksLikeLogits: Bool? = nil) -> [UInt8] {
        let logits = looksLikeLogits ?? (values.contains { $0 < 0 || $0 > 1 })
        return values.map { v in
            let p = logits ? 1 / (1 + exp(-v)) : v
            return UInt8((min(max(p, 0), 1) * 255).rounded())
        }
    }

    /// The hair plane of a model output with `shape` such as [h, w], [1, h, w], [1, 1, h, w] or [1, c, h, w] (channel `channel` is hair).
    static func extract(_ flat: [Float], shape: [Int], channel: Int = 0) -> (plane: [Float], width: Int, height: Int)? {
        guard shape.count >= 2, shape.allSatisfy({ $0 > 0 }) else { return nil }
        let h = shape[shape.count - 2], w = shape[shape.count - 1]
        let channels = shape.count >= 3 ? shape[shape.count - 3] : 1
        guard flat.count >= channels * h * w, channel < channels else { return nil }
        let start = channel * h * w
        return (Array(flat[start..<start + h * w]), w, h)
    }
}

/// Reads a model's output array as a mask plane at its own size, for the shapes segmentation models use.
enum MaskModelOutput {
    /// Class maps (`classIndex` set) become 0/255 where the class matches; probability or logit planes are squashed to 0...255.
    static func plane(_ arr: MLMultiArray, channel: Int = 0, classIndex: Int?) -> (bytes: [UInt8], width: Int, height: Int)? {
        let shape = arr.shape.map(\.intValue)
        guard let p = MaskDecode.extract(floats(arr), shape: shape, channel: channel) else { return nil }
        if let classIndex { return (p.plane.map { Int($0.rounded()) == classIndex ? 255 : 0 }, p.width, p.height) }
        return (MaskDecode.plane(p.plane), p.width, p.height)
    }

    static func floats(_ arr: MLMultiArray) -> [Float] {
        let n = arr.count
        switch arr.dataType {
        case .float32: return Array(UnsafeBufferPointer(start: arr.dataPointer.assumingMemoryBound(to: Float.self), count: n))
        case .float16: return Array(UnsafeBufferPointer(start: arr.dataPointer.assumingMemoryBound(to: Float16.self), count: n)).map(Float.init)
        default: return (0..<n).map { arr[$0].floatValue }
        }
    }

    static func image(_ bytes: [UInt8], width: Int, height: Int) -> CIImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return CIImage(cgImage: cg)
    }
}

/// Hair mask from the Core ML model in the `hairSegmentation` slot (face parsing by default; see docs/models.md).
/// The model works on a square window, so each face gets its own window around the head: far more pixels on the hair than one pass over the whole photo.
struct ModelHairMasker: HairMasking {
    var store: ModelStore = .shared
    var channel = 0
    var faces: FaceFinding?

    /// Square window (pixels, y-up like Core Image) around a face box that takes in the hair: a little above centre.
    static func window(forFace box: CGRect, in extent: CGRect) -> CGRect {
        let w = box.width * extent.width, h = box.height * extent.height
        let side = max(w, h) * 2.3
        let cx = extent.minX + box.midX * extent.width, cy = extent.minY + box.midY * extent.height + side * 0.1
        return CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
    }

    func hairMasks(in image: CIImage) throws -> [CIImage] {
        let (model, entry) = try store.load(.hairSegmentation)
        let e = image.extent
        let found = (try? (faces ?? Renderer.services.faceFinder)?.faceBoxes(in: image)) ?? []
        let windows = found.isEmpty ? [CGRect(x: e.midX - max(e.width, e.height) / 2, y: e.midY - max(e.width, e.height) / 2, width: max(e.width, e.height), height: max(e.width, e.height))]
                                    : found.map { Self.window(forFace: $0, in: e) }
        var total = CIImage(color: .black).cropped(to: e)
        for w in windows {
            guard let part = try mask(in: image, window: w, model: model, entry: entry) else { continue }
            total = part.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: total]).cropped(to: e)
        }
        return [total]
    }

    private func mask(in image: CIImage, window: CGRect, model: MLModel, entry: ModelEntry) throws -> CIImage? {
        let side = entry.side ?? 512
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb) == kCVReturnSuccess, let pb else { throw InpaintError.bufferFailed }
        let crop = image.clampedToExtent().cropped(to: window).transformed(by: CGAffineTransform(translationX: -window.minX, y: -window.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(side) / window.width, y: CGFloat(side) / window.height))
        CIContext().render(crop, to: pb, bounds: CGRect(x: 0, y: 0, width: side, height: side), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [entry.io["input"] ?? "input": MLFeatureValue(pixelBuffer: pb)]))
        guard let f = out.featureValue(for: entry.io["output"] ?? "output") else { throw InpaintError.predictionFailed }
        let small: CIImage
        if let buf = f.imageBufferValue {
            small = CIImage(cvPixelBuffer: buf).applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0)])
        } else if let arr = f.multiArrayValue {
            guard let p = MaskModelOutput.plane(arr, channel: channel, classIndex: entry.classIndex), let img = MaskModelOutput.image(p.bytes, width: p.width, height: p.height) else { throw InpaintError.predictionFailed }
            small = img
        } else { throw InpaintError.predictionFailed }
        // soften the hard class edge a little before scaling it to the window
        let soft = small.clampedToExtent().applyingGaussianBlur(sigma: entry.classIndex == nil ? 0 : 1.2).cropped(to: small.extent)
        return soft.transformed(by: CGAffineTransform(scaleX: window.width / small.extent.width, y: window.height / small.extent.height)).transformed(by: CGAffineTransform(translationX: window.minX, y: window.minY)).cropped(to: window.intersection(image.extent))
    }
}

/// Uses the installed hair model when there is one, the colour-and-skin estimate otherwise (and when the model fails).
struct AdaptiveHairMasker: HairMasking {
    var estimate: HairMasking
    var store: ModelStore = .shared
    func hairMasks(in image: CIImage) throws -> [CIImage] {
        if store.isAvailable(.hairSegmentation), let m = try? ModelHairMasker(store: store).hairMasks(in: image), !m.isEmpty { return m }
        return try estimate.hairMasks(in: image)
    }
}
