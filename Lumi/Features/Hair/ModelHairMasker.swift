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

/// Hair mask from a Core ML segmentation model installed in the `hairSegmentation` slot (see docs/models.md).
struct ModelHairMasker: HairMasking {
    var store: ModelStore = .shared
    var channel = 0

    func hairMasks(in image: CIImage) throws -> [CIImage] {
        let (model, entry) = try store.load(.hairSegmentation)
        let side = entry.side ?? 512
        let e = image.extent
        let ctx = CIContext()
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb) == kCVReturnSuccess, let pb else { throw InpaintError.bufferFailed }
        let scaled = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(side) / e.width, y: CGFloat(side) / e.height))
        ctx.render(scaled, to: pb, bounds: CGRect(x: 0, y: 0, width: side, height: side), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [entry.io["input"] ?? "input": MLFeatureValue(pixelBuffer: pb)]))
        guard let f = out.featureValue(for: entry.io["output"] ?? "output") else { throw InpaintError.predictionFailed }
        let small: CIImage
        if let buf = f.imageBufferValue {
            small = CIImage(cvPixelBuffer: buf).applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0)])
        } else if let arr = f.multiArrayValue {
            let flat = (0..<arr.count).map { arr[$0].floatValue }
            guard let p = MaskDecode.extract(flat, shape: arr.shape.map(\.intValue), channel: channel) else { throw InpaintError.predictionFailed }
            let bytes = MaskDecode.plane(p.plane)
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let cg = CGImage(width: p.width, height: p.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: p.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw InpaintError.predictionFailed }
            small = CIImage(cgImage: cg)
        } else { throw InpaintError.predictionFailed }
        let mask = small.transformed(by: CGAffineTransform(scaleX: e.width / small.extent.width, y: e.height / small.extent.height)).transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY)).cropped(to: e)
        return [mask]
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
