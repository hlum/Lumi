import CoreImage
import CoreML
import Foundation

/// Pure helpers for the Stable Diffusion inpainting pipeline (tested without the models).
enum DiffusionMath {
    static let side = 512, latentSide = 64, scale: Float = 0.18215

    /// The 512x512 binary mask as the 64x64 latent mask: one sample per 8x8 block, centre pixel.
    static func latentMask(_ mask: [UInt8]) -> [Float] {
        (0..<latentSide * latentSide).map { i in
            let x = (i % latentSide) * 8 + 4, y = (i / latentSide) * 8 + 4
            return mask[y * side + x] > 127 ? 1 : 0
        }
    }

    /// Text-encoder output [77, 768] (row per token) in the layout the UNet wants: [768, 1, 77], channels first.
    static func conditioning(_ hidden: [Float], tokens: Int = 77, width: Int = 768) -> [Float] {
        var out = [Float](repeating: 0, count: tokens * width)
        for t in 0..<tokens { for c in 0..<width { out[c * tokens + t] = hidden[t * width + c] } }
        return out
    }

    /// The UNet's 9 input channels: noisy latents, mask, latents of the masked picture.
    static func unetSample(latents: [Float], mask: [Float], masked: [Float]) -> [Float] { latents + mask + masked }

    /// Classifier-free guidance: push the prediction away from the unconditioned one.
    static func guided(uncond: [Float], cond: [Float], scale: Float) -> [Float] {
        zip(uncond, cond).map { $0 + scale * ($1 - $0) }
    }

    /// RGBA8 window pixels to the VAE's CHW input in -1...1, with masked pixels blanked (the model fills what it can't see).
    static func maskedPlanes(rgba: [UInt8], mask: [UInt8]) -> [Float] {
        let n = side * side
        var out = [Float](repeating: 0, count: 3 * n)
        for i in 0..<n where mask[i] <= 127 {
            for c in 0..<3 { out[c * n + i] = Float(rgba[i * 4 + c]) / 127.5 - 1 }
        }
        return out
    }

    /// VAE decoder output (CHW, -1...1) to RGBA8.
    static func rgba(fromPlanes p: [Float]) -> [UInt8] {
        let n = side * side
        var out = [UInt8](repeating: 255, count: 4 * n)
        for i in 0..<n { for c in 0..<3 { out[i * 4 + c] = UInt8(min(max((p[c * n + i] / 2 + 0.5) * 255, 0), 255).rounded()) } }
        return out
    }
}

/// Stable Diffusion 1.5 inpainting (DreamShaper 8, Core ML fp16) as the object-removal and fill model. Slow, and by far the best fill.
/// Runs on a 512 window around the mask, then blends only the masked area back into the full-resolution photo.
final class DiffusionInpainter: Inpainting {
    static let folder = "SDInpaint"
    static let prompt = "clean natural background, seamless, photorealistic, highly detailed"
    static let negative = "text, watermark, people, person, object, blurry, deformed, artifacts"

    /// Where the downloaded model lives (Settings > AI models installs it here).
    static var installDirectory: URL { ModelStore.shared.installedDirectory.appendingPathComponent(folder, isDirectory: true) }

    /// The model folder when every file is there, else nil.
    static func directory() -> URL? {
        let u = installDirectory
        return DiffusionDownload.isComplete(at: u) ? u : nil
    }
    static var isAvailable: Bool { directory() != nil }

    private let dir: URL
    private let steps: Int, guidance: Float
    private let context = CIContext()
    private var models: Models?
    private let lock = NSLock()

    private struct Models { var text, chunk1, chunk2, encoder, decoder: MLModel; var tokenizer: CLIPTokenizer }

    init(directory: URL, steps: Int = 20, guidance: Float = 7) { dir = directory; self.steps = steps; self.guidance = guidance }

    /// Frees the ~2 GB of weights; the next fill loads them again.
    func unload() { lock.lock(); models = nil; lock.unlock() }

    private func load() throws -> Models {
        lock.lock(); defer { lock.unlock() }
        if let models { return models }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .cpuAndGPU
        func m(_ n: String) throws -> MLModel { try MLModel(contentsOf: dir.appendingPathComponent(n + ".mlmodelc"), configuration: cfg) }
        let loaded = Models(text: try m("TextEncoder"), chunk1: try m("UnetChunk1"), chunk2: try m("UnetChunk2"), encoder: try m("VAEEncoder"), decoder: try m("VAEDecoder"),
                            tokenizer: try CLIPTokenizer(vocabURL: dir.appendingPathComponent("vocab.json"), mergesURL: dir.appendingPathComponent("merges.txt")))
        models = loaded
        return loaded
    }

    func inpaint(_ image: CIImage, mask: CIImage) throws -> CIImage {
        let extent = image.extent
        let w = Int(extent.width), h = Int(extent.height)
        var maskPixels = [UInt8](repeating: 0, count: w * h)
        context.render(mask.cropped(to: extent), toBitmap: &maskPixels, rowBytes: w, bounds: extent, format: .L8, colorSpace: nil)
        let mb = InpaintPlan.bounds(ofMask: maskPixels, width: w, height: h)
        guard let crop = InpaintPlan.cropRect(maskBounds: mb, imageSize: extent.size, context: 0.6, minSide: 320) else { throw InpaintError.emptyMask }

        let side = CGFloat(DiffusionMath.side)
        func window(_ img: CIImage) -> CIImage {
            let c = img.cropped(to: crop.offsetBy(dx: extent.minX, dy: extent.minY))
            return c.transformed(by: CGAffineTransform(translationX: -c.extent.minX, y: -c.extent.minY).scaledBy(x: side / crop.width, y: side / crop.height))
        }
        let n = DiffusionMath.side * DiffusionMath.side, box = CGRect(x: 0, y: 0, width: side, height: side)
        var rgba = [UInt8](repeating: 0, count: n * 4)
        context.render(window(image), toBitmap: &rgba, rowBytes: DiffusionMath.side * 4, bounds: box, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        // a slightly grown, hard mask: the model must repaint the edge of what was there too
        let hard = window(mask).clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 5]).cropped(to: box)
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 40, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 40, y: 0, z: 0, w: 0), "inputBVector": CIVector(x: 40, y: 0, z: 0, w: 0)])
            .applyingFilter("CIColorClamp")
        var winMask = [UInt8](repeating: 0, count: n)
        context.render(hard, toBitmap: &winMask, rowBytes: DiffusionMath.side, bounds: box, format: .L8, colorSpace: nil)

        let out = try run(rgba: rgba, mask: winMask)

        guard let provider = CGDataProvider(data: Data(out) as CFData),
              let cg = CGImage(width: DiffusionMath.side, height: DiffusionMath.side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: DiffusionMath.side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw InpaintError.predictionFailed }
        let result = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: crop.width / side, y: crop.height / side))
            .transformed(by: CGAffineTransform(translationX: crop.minX + extent.minX, y: crop.minY + extent.minY))
        let grown = mask.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 4])
            .applyingGaussianBlur(sigma: 2.5).cropped(to: extent)
        let blend = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: result.cropped(to: extent), kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: grown])!
        return blend.outputImage!.cropped(to: extent)
    }

    // MARK: the diffusion loop

    private func run(rgba: [UInt8], mask: [UInt8]) throws -> [UInt8] {
        let m = try load()
        let ls = DiffusionMath.latentSide, latentCount = 4 * ls * ls

        // what the model can see: the picture with the hole blanked, as a latent
        let planes = DiffusionMath.maskedPlanes(rgba: rgba, mask: mask)
        let moments = try Self.floats(try m.encoder.prediction(from: Self.provider(["x": Self.array(planes, shape: [1, 3, 512, 512], type: .float16)])).featureValue(for: "latent")!.multiArrayValue!)
        let masked = moments[0..<latentCount].map { $0 * DiffusionMath.scale }            // first 4 of 8 channels = the distribution's mean
        let maskLatent = DiffusionMath.latentMask(mask)

        let uncond = try encodeText(Self.negative, m), cond = try encodeText(Self.prompt, m)
        let hidden = try Self.array(uncond + cond, shape: [2, 768, 1, 77], type: .float16)

        let scheduler = DDIMScheduler(steps: steps)
        var noise = SeededNormal(seed: UInt64(truncatingIfNeeded: mask.reduce(5381) { ($0 &* 33) &+ Int($1) }))
        var latents = noise.array(latentCount)
        for t in scheduler.timesteps {
            let one = DiffusionMath.unetSample(latents: latents, mask: maskLatent, masked: masked)
            let sample = try Self.array(one + one, shape: [2, 9, 64, 64], type: .float16)
            let step = try Self.array([Float(t), Float(t)], shape: [2], type: .float16)
            let a = try m.chunk1.prediction(from: Self.provider(["sample": sample, "timestep": step, "encoder_hidden_states": hidden]))
            var inputs: [String: MLFeatureValue] = ["encoder_hidden_states": MLFeatureValue(multiArray: hidden)]
            for name in m.chunk2.modelDescription.inputDescriptionsByName.keys where name != "encoder_hidden_states" {
                guard let v = a.featureValue(for: name) else { throw InpaintError.predictionFailed }
                inputs[name] = v
            }
            let b = try m.chunk2.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
            guard let eps = b.featureValue(for: "noise_pred")?.multiArrayValue else { throw InpaintError.predictionFailed }
            let both = try Self.floats(eps)
            let guided = DiffusionMath.guided(uncond: Array(both[0..<latentCount]), cond: Array(both[latentCount..<2 * latentCount]), scale: guidance)
            latents = scheduler.step(sample: latents, noise: guided, t: t)
        }

        let z = try Self.array(latents.map { $0 / DiffusionMath.scale }, shape: [1, 4, 64, 64], type: .float16)
        guard let img = try m.decoder.prediction(from: Self.provider(["z": z])).featureValue(for: "image")?.multiArrayValue else { throw InpaintError.predictionFailed }
        return DiffusionMath.rgba(fromPlanes: try Self.floats(img))
    }

    /// Text-encoder hidden states in the UNet's channel-first layout.
    private func encodeText(_ text: String, _ m: Models) throws -> [Float] {
        let ids = m.tokenizer.encode(text).map(Float.init)
        let out = try m.text.prediction(from: Self.provider(["input_ids": Self.array(ids, shape: [1, 77], type: .float32)]))
        guard let h = out.featureValue(for: "last_hidden_state")?.multiArrayValue else { throw InpaintError.predictionFailed }
        return DiffusionMath.conditioning(try Self.floats(h))
    }

    // MARK: Core ML plumbing

    private static func provider(_ d: [String: MLMultiArray]) -> MLDictionaryFeatureProvider { try! MLDictionaryFeatureProvider(dictionary: d.mapValues { MLFeatureValue(multiArray: $0) }) }

    private static func array(_ values: [Float], shape: [Int], type: MLMultiArrayDataType) throws -> MLMultiArray {
        let a = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: type)
        if type == .float16 { let p = a.dataPointer.assumingMemoryBound(to: Float16.self); for i in 0..<values.count { p[i] = Float16(values[i]) } }
        else { let p = a.dataPointer.assumingMemoryBound(to: Float.self); for i in 0..<values.count { p[i] = values[i] } }
        return a
    }

    /// Reads through MLShapedArray so padded (non-contiguous) output layouts come out right.
    private static func floats(_ a: MLMultiArray) throws -> [Float] { MLShapedArray<Float32>(a).scalars }
}
