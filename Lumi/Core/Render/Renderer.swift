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
        var faceFinder: FaceFinding?
        var textFinder: TextFinding?
        var upscaler: Upscaling?
        var colorizer: Colorizing?
        var faceLandmarker: FaceLandmarking?
        /// Last detected faces, kept so slider drags don't re-run detection every frame.
        fileprivate var faceCache: (key: String, faces: [FaceInfo])?
        private(set) var faceCacheKeyCount = 0
        fileprivate func remember(faces: [FaceInfo], key: String) { faceCache = (key, faces); faceCacheKeyCount += 1 }
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
        var beforeFilter: CIImage?
        for (i, op) in document.operations.enumerated() {
            switch op {
            case .exposure(let v): img = render(img, exposure: v)
            case .crop(let c): img = GeometryOps.apply(c, to: img)
            case .adjust(let a): img = AdjustOps.apply(a, to: img)
            case .curve(let c): img = AdjustOps.apply(c, to: img)
            case .warp(let w): img = MeshWarpRenderer.apply(w.field, to: img)
            case .layers(let l): img = layered(l, over: img, prefix: Array(document.operations[0..<i]))
            case .remove(let masks): img = removed(masks, from: img, prefix: Array(document.operations[0...i]))
            case .filter(let id, let t): beforeFilter = img; img = FilterLibrary.shared.lut(id)?.apply(to: img, intensity: t) ?? img
            case .filterEraser(let m):
                // brushed areas get the unfiltered picture back
                if let original = beforeFilter, original.extent == img.extent {
                    let f = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: original, kCIInputBackgroundImageKey: img, kCIInputMaskImageKey: MaskScaling.scaled(m, to: img.extent)])!
                    img = f.outputImage?.cropped(to: img.extent) ?? img
                }
            case .mosaic(let c): img = mosaiced(c, from: img, prefix: Array(document.operations[0..<i]))
            case .watermark(let w): img = WatermarkRenderer.apply(w, to: img)
            case .face(let f): img = retouched(f, from: img, prefix: Array(document.operations[0..<i]))
            case .grade(let g): img = g.lut().apply(to: img)
            case .colorize(let t): img = colorized(t, from: img, prefix: Array(document.operations[0..<i]))
            case .upscale(let f): img = upscaled(f, from: img, prefix: Array(document.operations[0..<i]))
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

    static func mosaiced(_ c: MosaicConfig, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        var faces: [CGRect] = []
        if c.coverFaces, let finder = services.faceFinder {
            let key = "faces|" + cacheKey(image, prefix)
            // faces are cached as a mask-free marker image: store the rects by drawing them (cheap) so the cache type stays CIImage
            let boxes = (try? finder.faceBoxes(in: image)) ?? []
            _ = key
            faces = boxes
        }
        var text: [CGRect] = []
        if c.chatMode, let finder = services.textFinder { text = (try? finder.textBoxes(in: image)) ?? [] }
        return MosaicRender.apply(c, to: image, faces: faces, textBoxes: text)
    }

    static func upscaled(_ factor: Int, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard let up = services.upscaler, [2, 4].contains(factor) else { return image }
        let key = "up|" + cacheKey(image, prefix)
        guard let big = (try? services.cached(key) { try up.upscale4x(image) }) ?? nil else { return image }
        guard factor == 2 else { return big }
        return big.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))            // 4x result brought to 2x
    }

    static func colorized(_ strength: Double, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard let c = services.colorizer, strength > 0 else { return image }
        let key = "colorize|" + cacheKey(image, prefix)
        guard let full = (try? services.cached(key) { try c.colorize(image) }) ?? nil else { return image }
        guard strength < 1 else { return full }
        let mix = CIFilter(name: "CIDissolveTransition", parameters: [kCIInputImageKey: image, kCIInputTargetImageKey: full, kCIInputTimeKey: strength])!
        return mix.outputImage?.cropped(to: image.extent) ?? full
    }

    static func retouched(_ f: FaceRetouch, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard !f.isIdentity, let finder = services.faceLandmarker else { return image }
        let key = "face|" + cacheKey(image, prefix)
        let faces: [FaceInfo]
        if let c = services.faceCache, c.key == key { faces = c.faces }
        else { faces = (try? finder.faces(in: image)) ?? []; services.remember(faces: faces, key: key) }
        return FaceRetouchRender.apply(f, to: image, faces: faces)
    }

    /// Layers flagged "behind subject" need the subject mask; it is found once per (image, earlier ops) and reused.
    static func layered(_ stack: LayerStack, over image: CIImage, prefix: [EditOperation]) -> CIImage {
        var mask: CIImage?
        if stack.layers.contains(where: \.behindSubject), let masker = services.subjectMasker {
            mask = (try? services.cached("mask|" + cacheKey(image, prefix)) { try masker.subjectMask(for: image) }) ?? nil
        }
        return LayerRenderer.render(stack, over: image, subjectMask: mask)
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
