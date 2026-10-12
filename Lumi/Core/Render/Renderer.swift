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
        var peopleFinder: PeopleFinding?
        var objectFinder: ObjectFinding?
        var hairMasker: HairMasking?
        var upscaler: Upscaling?
        var colorizer: Colorizing?
        var faceLandmarker: FaceLandmarking?
        var bodyFinder: BodyFinding?
        var handFinder: HandFinding?
        // renders can run on a background task while the main thread renders another preview, so every cache goes through this lock (never held while a model runs)
        private let lock = NSLock()
        private var _bodyCache: (key: String, poses: [[String: CGPoint]])?
        private var _faceCache: (key: String, faces: [FaceInfo])?
        fileprivate var bodyCache: (key: String, poses: [[String: CGPoint]])? { get { lock.withLock { _bodyCache } } set { lock.withLock { _bodyCache = newValue } } }
        /// Last detected faces, kept so slider drags don't re-run detection every frame.
        fileprivate var faceCache: (key: String, faces: [FaceInfo])? { get { lock.withLock { _faceCache } } set { lock.withLock { _faceCache = newValue } } }
        private(set) var faceCacheKeyCount = 0
        fileprivate func remember(faces: [FaceInfo], key: String) { lock.withLock { _faceCache = (key, faces); faceCacheKeyCount += 1 } }
        private var cache: [String: CIImage] = [:]
        private(set) var inpaintCalls = 0
        private(set) var keysSeen: [String] = []
        init(inpainter: Inpainting? = nil) { self.inpainter = inpainter }
        func cached(_ key: String, _ make: () throws -> CIImage?) rethrows -> CIImage? {
            let hit: CIImage? = lock.withLock { keysSeen.append(key); return cache[key] }
            if let hit { return hit }
            guard let v = try make() else { return nil }
            lock.withLock {
                if cache.count > 8 { cache.removeAll() }
                cache[key] = v; inpaintCalls += 1
            }
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
            case .warp(let w): img = MeshWarpRenderer.apply(w.field(aspect: Float(img.extent.width / max(img.extent.height, 1))), to: img)
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
            case .clean(let c): img = CleanOps.apply(c, to: img)
            case .match(let m): img = m.apply(to: img)
            case .relight(let r): img = relit(r, from: img, prefix: Array(document.operations[0..<i]))
            case .effect(let e): img = PhotoEffect.apply(e.effect, strength: e.strength, to: img)
            case .body(let b): img = bodyRetouched(b, from: img, prefix: Array(document.operations[0..<i]))
            case .hair(let h): img = hairRetouched(h, from: img, prefix: Array(document.operations[0..<i]))
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
        guard !f.isIdentity else { return image }
        // nails come from hand pose, not from faces, so a photo of a hand works
        var base = image
        if !f.nails.isIdentity, let hands = services.handFinder { base = NailRenderer.paint(NailRegions.find(in: image, finder: hands), f.nails, to: image) }
        guard let finder = services.faceLandmarker else { return base }
        let image = base
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

    static func relit(_ r: RelightConfig, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard !r.isIdentity else { return image }
        var faces: [FaceInfo] = []
        let needsFaces = [RelightStyle.backlit, .flash, .fillLight, .photoBooth, .ledStrip, .redLight, .goldenHour].contains(r.style)
        if needsFaces, let finder = services.faceLandmarker {
            let key = "faces|" + cacheKey(image, prefix)
            if let c = services.faceCache, c.key == key { faces = c.faces } else { faces = (try? finder.faces(in: image)) ?? []; services.remember(faces: faces, key: key) }
        }
        var mask: CIImage?
        if r.style != .night, r.style != .backlit, let masker = services.subjectMasker {
            mask = (try? services.cached("mask|" + cacheKey(image, prefix)) { try masker.subjectMask(for: image) }) ?? nil
        }
        return RelightOps.apply(r, to: image, faces: faces, personMask: mask)
    }

    static func bodyRetouched(_ b: BodyRetouch, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard !b.isIdentity, let finder = services.bodyFinder else { return image }
        let key = "body|" + cacheKey(image, prefix)
        let poses: [[String: CGPoint]]
        if let c = services.bodyCache, c.key == key { poses = c.poses } else { poses = (try? finder.poses(in: image)) ?? []; services.bodyCache = (key, poses) }
        var mask: CIImage?
        if b.protectBackground, let masker = services.subjectMasker { mask = (try? services.cached("mask|" + cacheKey(image, prefix)) { try masker.subjectMask(for: image) }) ?? nil }
        return BodyRetouchRender.apply(b, to: image, poses: poses, personMask: mask, inpainter: services.inpainter)
    }

    static func hairRetouched(_ h: HairRetouch, from image: CIImage, prefix: [EditOperation]) -> CIImage {
        guard !h.isIdentity else { return image }
        guard let masker = services.hairMasker else { return image }
        // the estimated hair masks depend only on the pixels before this step, so slider drags reuse them
        let key = "hair|" + cacheKey(image, prefix)
        let first = try? services.cached(key) { try masker.hairMasks(in: image).first }
        var faces: [FaceInfo] = []
        if h.volume != 0 || h.hairline != 0, let finder = services.faceLandmarker {
            let fk = "faces|" + cacheKey(image, prefix)
            if let c = services.faceCache, c.key == fk { faces = c.faces } else { faces = (try? finder.faces(in: image)) ?? []; services.remember(faces: faces, key: fk) }
        }
        return HairRetouchRender.apply(h, to: image, hairMasks: first.flatMap { $0 }.map { [$0] } ?? [], faces: faces, inpainter: services.inpainter)
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
