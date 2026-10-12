import CoreImage
import CoreML

/// Person/foreground mask from the model in the `personMatting` slot (BiRefNet by default), with Apple's Vision mask as the fallback.
struct ModelSubjectMasker: SubjectMasking {
    var store: ModelStore = .shared

    static let mean: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]

    func subjectMask(for image: CIImage) throws -> CIImage? {
        let (model, entry) = try store.load(.personMatting)
        let side = entry.side ?? 1024, e = image.extent
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb) == kCVReturnSuccess, let pb else { throw InpaintError.bufferFailed }
        let scaled = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(side) / e.width, y: CGFloat(side) / e.height))
        CIContext().render(scaled, to: pb, bounds: CGRect(x: 0, y: 0, width: side, height: side), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let inName = entry.io["input"] ?? "input"
        let feature: MLFeatureValue
        if entry.normalize == "imagenet" { feature = MLFeatureValue(multiArray: try Self.array(from: pb, side: side, dataType: model.modelDescription.inputDescriptionsByName[inName]?.multiArrayConstraint?.dataType ?? .float16)) } else { feature = MLFeatureValue(pixelBuffer: pb) }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inName: feature]))
        guard let arr = out.featureValue(for: entry.io["output"] ?? "output")?.multiArrayValue,
              let p = MaskModelOutput.plane(arr, classIndex: entry.classIndex), let small = MaskModelOutput.image(p.bytes, width: p.width, height: p.height) else { throw InpaintError.predictionFailed }
        let mask = small.transformed(by: CGAffineTransform(scaleX: e.width / small.extent.width, y: e.height / small.extent.height)).transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY)).cropped(to: e)
        return ProtectedWarp.hasContent(mask) ? mask : nil
    }

    /// 1 x 3 x side x side, float16 or float32, ImageNet-normalised, from a BGRA buffer.
    static func array(from pb: CVPixelBuffer, side: Int, dataType: MLMultiArrayDataType = .float16) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: [1, 3, NSNumber(value: side), NSNumber(value: side)], dataType: dataType)
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb)?.assumingMemoryBound(to: UInt8.self) else { throw InpaintError.bufferFailed }
        let stride = CVPixelBufferGetBytesPerRow(pb), plane = side * side
        let half = dataType == .float16
        let f16 = arr.dataPointer.assumingMemoryBound(to: Float16.self), f32 = arr.dataPointer.assumingMemoryBound(to: Float.self)
        func put(_ i: Int, _ v: Float) { if half { f16[i] = Float16(v) } else { f32[i] = v } }
        for y in 0..<side {
            let row = base + y * stride
            for x in 0..<side {
                let o = x * 4, i = y * side + x
                put(i, (Float(row[o + 2]) / 255 - mean[0]) / std[0])
                put(plane + i, (Float(row[o + 1]) / 255 - mean[1]) / std[1])
                put(2 * plane + i, (Float(row[o]) / 255 - mean[2]) / std[2])
            }
        }
        return arr
    }
}

/// The installed matting model when there is one; Apple's foreground mask otherwise, or when the model fails.
struct AdaptiveSubjectMasker: SubjectMasking {
    var fallback: SubjectMasking
    var store: ModelStore = .shared
    func subjectMask(for image: CIImage) throws -> CIImage? {
        if store.isAvailable(.personMatting), let m = try? ModelSubjectMasker(store: store).subjectMask(for: image) { return m }
        return try fallback.subjectMask(for: image)
    }
}
