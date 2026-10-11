import CoreImage
import CryptoKit
import CoreImage.CIFilterBuiltins

/// Pure function of its inputs: same image + parameters give the same output.
enum Renderer {
    static func render(_ frame: CIImage, exposure: Double) -> CIImage {
        guard exposure != 0 else { return frame }
        let f = CIFilter.exposureAdjust()
        f.inputImage = frame
        f.ev = Float(exposure)
        return f.outputImage ?? frame
    }

    /// Shared services the render graph may need (the inpainter). Set once at launch; tests inject fakes.
    final class Services {
        var inpainter: Inpainting?
        var subjectMasker: SubjectMasking?
        private var cache: [String: CIImage] = [:]
        private(set) var inpaintCalls = 0
        private(set) var keysSeen: [String] = []
        init(inpainter: Inpainting? = nil) { self.inpainter = inpainter }
        func cached(_ key: String, _ make: () throws -> CIImage?) rethrows -> CIImage? {
            keysSeen.append(key)
            if let c = cache[key] { return c }
            guard let v = try make() else { return nil }
            if cache.count > 8 { cache.removeAll() }
            cache[key] = v; inpaintCalls += 1
            return v
        }
    }
    nonisolated(unsafe) static var services = Services()

    static func render(_ frame: CIImage, document: EditDocument) -> CIImage {
        var img = frame
        for (i, op) in document.operations.enumerated() {
            switch op {
            case .exposure(let v): img = render(img, exposure: v)
            case .crop(let c): img = GeometryOps.apply(c, to: img)
            case .adjust(let a): img = AdjustOps.apply(a, to: img)
            case .curve(let c): img = AdjustOps.apply(c, to: img)
            case .warp(let w): img = MeshWarpRenderer.apply(w.field, to: img)
            case .layers(let l): img = LayerRenderer.render(l, over: img)
            case .remove(let masks): img = removed(masks, from: img, prefix: Array(document.operations[0...i]))
            case .filter(let id, let t): img = FilterLibrary.shared.lut(id)?.apply(to: img, intensity: t) ?? img
            case .frame(let c): img = FrameOps.apply(c, to: img)
            case .doodle(let d): img = Doodle.render(d, over: img)
            case .expand(let c): img = expanded(c, from: img, prefix: Array(document.operations[0..<i]))
            case .cutout(let c): img = cutOut(c, from: img, prefix: Array(document.operations[0..<i]))
            }
        }
        return img
    }

    /// The subject mask depends only on the pixels before this op, so it is cached per (image size, earlier ops).
    static func cutOut(_ c: CutoutConfig, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard let masker = services.subjectMasker else { return image }
        let key = "mask|" + cacheKey(image, prefix)
        guard let mask = (try? services.cached(key) { try masker.subjectMask(for: image) }) ?? nil else { return image }
        return CutoutOps.apply(c, to: image, subjectMask: mask)
    }

    static func expanded(_ c: ExpandConfig, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard let inpainter = services.inpainter, !c.isIdentity else { return image }
        let key = "expand|\(c)|" + cacheKey(image, prefix)
        return (try? services.cached(key) { try ExpandOps.apply(c, to: image, inpainter: inpainter) }) ?? image
    }

    static func cacheKey(_ image: CIImage, _ prefix: [EditOperation]) -> String {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: (try? enc.encode(prefix)) ?? Data())
        return "\(image.extent.size)|" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Runs the inpainter once per (operations so far, image size); later renders reuse the result.
    static func removed(_ masks: [MaskCanvas], from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard let inpainter = services.inpainter else { return image }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: (try? enc.encode(prefix)) ?? Data())
        let key = "\(image.extent.size)|" + digest.map { String(format: "%02x", $0) }.joined()
        return (try? services.cached(key) {
            try masks.reduce(image) { acc, m in
                let big = MaskScaling.scaled(m, to: image.extent)
                return try inpainter.inpaint(acc, mask: big)
            }
        }) ?? image
    }

    /// Downscale so the longest side is at most `maxDimension`; never upscales.
    static func proxy(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let longest = max(image.extent.width, image.extent.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let s = maxDimension / longest
        return image.transformed(by: CGAffineTransform(scaleX: s, y: s))
    }
}
