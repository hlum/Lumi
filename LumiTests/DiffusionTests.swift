import CoreImage
import Testing
@testable import Lumi

@Suite(.serialized)
struct DiffusionTests {
    static let modelDir = DiffusionInpainter.directory()

    @Test func timestepsRunFromNoisyToCleanWithTheOffset() {
        let s = DDIMScheduler(steps: 20)
        #expect(s.timesteps.count == 20 && s.timesteps.first == 951 && s.timesteps.last == 1)
        #expect(zip(s.timesteps, s.timesteps.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test func aStepWithTheTrueNoiseLandsOnTheCleanSignal() {
        let s = DDIMScheduler(steps: 10)
        // x_t built from x0 and eps at t = 501, as training does; stepping to the previous t must keep both in the same proportions
        let x0: [Float] = [1, -1, 0.5], eps: [Float] = [0.2, 0.4, -0.3]
        func alpha(_ t: Int) -> Double {
            var a = 1.0
            for i in 0...t { let b = pow(sqrt(0.00085) + (sqrt(0.012) - sqrt(0.00085)) * Double(i) / 999, 2); a *= 1 - b }
            return a
        }
        let t = 501, prev = 401
        let xt = (0..<3).map { Float(alpha(t).squareRoot()) * x0[$0] + Float((1 - alpha(t)).squareRoot()) * eps[$0] }
        let out = s.step(sample: xt, noise: eps, t: t)
        for i in 0..<3 { #expect(abs(out[i] - (Float(alpha(prev).squareRoot()) * x0[i] + Float((1 - alpha(prev)).squareRoot()) * eps[i])) < 1e-4) }
    }

    @Test func noiseIsDeterministicAndRoughlyStandardNormal() {
        var a = SeededNormal(seed: 7), b = SeededNormal(seed: 7)
        let x = a.array(20000)
        #expect(x == b.array(20000))
        let mean = x.reduce(0, +) / Float(x.count), variance = x.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(x.count)
        #expect(abs(mean) < 0.03 && abs(variance - 1) < 0.05)
    }

    @Test func latentMaskSamplesTheCentreOfEachBlock() {
        var m = [UInt8](repeating: 0, count: 512 * 512)
        for y in 0..<512 { for x in 0..<256 { m[y * 512 + x] = 255 } }                  // left half masked
        let l = DiffusionMath.latentMask(m)
        #expect(l.count == 4096 && l[0] == 1 && l[31] == 1 && l[32] == 0 && l[63] == 0)
    }

    @Test func conditioningIsChannelFirst() {
        var h = [Float](repeating: 0, count: 77 * 768)
        h[5 * 768 + 9] = 3                                                                // token 5, channel 9
        #expect(DiffusionMath.conditioning(h)[9 * 77 + 5] == 3)
    }

    @Test func guidancePushesAwayFromTheUnconditionedPrediction() {
        #expect(DiffusionMath.guided(uncond: [1, 1], cond: [2, 0], scale: 7) == [8, -6])
    }

    @Test func maskedPlanesBlankTheHoleAndScaleToMinusOneToOne() {
        let n = 512 * 512
        var rgba = [UInt8](repeating: 255, count: n * 4)
        var mask = [UInt8](repeating: 0, count: n); mask[0] = 255
        let p = DiffusionMath.maskedPlanes(rgba: rgba, mask: mask)
        #expect(p[0] == 0 && p[n] == 0 && p[1] == 1)                                       // masked pixel blank, kept pixel white = 1
        rgba[0] = 0
        #expect(DiffusionMath.rgba(fromPlanes: [Float](repeating: -1, count: 3 * n))[0] == 0 && DiffusionMath.rgba(fromPlanes: [Float](repeating: 1, count: 3 * n))[0] == 255)
    }

    @Test func unetSampleIsLatentsThenMaskThenMaskedLatents() {
        let s = DiffusionMath.unetSample(latents: [1, 1], mask: [2], masked: [3, 3])
        #expect(s == [1, 1, 2, 3, 3])
    }

    @Test(.enabled(if: DiffusionTests.modelDir != nil)) func tokenizerMatchesClip() throws {
        let t = try CLIPTokenizer(vocabURL: DiffusionTests.modelDir!.appendingPathComponent("vocab.json"), mergesURL: DiffusionTests.modelDir!.appendingPathComponent("merges.txt"))
        #expect(Array(t.encode("a photo of a cat").prefix(7)) == [49406, 320, 1125, 539, 320, 2368, 49407])
        #expect(t.encode("").count == 77 && t.encode("").allSatisfy { $0 == 49406 || $0 == 49407 })
    }

    @Test(.enabled(if: DiffusionTests.modelDir != nil)) func fillsAHoleWithTheSurroundingsWhenTheModelIsInstalled() throws {
        // a long test run leaves too little memory: the pipeline then refuses (and the app falls back to LaMa) instead of letting the GPU abort
        guard DiffusionInpainter.hasRoom else { #expect(throws: InpaintError.self) { try DiffusionInpainter(directory: DiffusionTests.modelDir!).inpaint(CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)), mask: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))) }; return }
        let rect = CGRect(x: 0, y: 0, width: 512, height: 512)
        let sky = CIImage(color: CIColor(red: 0.3, green: 0.5, blue: 0.9)).cropped(to: rect)
        let blob = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 200, y: 200, width: 100, height: 100)).composited(over: sky)
        let hole = CIImage(color: .white).cropped(to: CGRect(x: 200, y: 200, width: 100, height: 100)).composited(over: CIImage(color: .black).cropped(to: rect))
        let out = try DiffusionInpainter(directory: DiffusionTests.modelDir!, steps: 8).inpaint(blob, mask: hole)
        #expect(out.extent == rect)
        let px = GeometryTests.rgb(out, x: 250, y: 250)
        #expect(!(px[0] > 200 && px[1] < 60), "the red blob is still there: \(px)")
        let far = zip(GeometryTests.rgb(out, x: 20, y: 20), GeometryTests.rgb(blob, x: 20, y: 20)).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
        #expect(far)                                                                       // outside the mask the photo is untouched
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first, let png = CIContext().pngRepresentation(of: out, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) { try? png.write(to: docs.appendingPathComponent("sd_fill.png")) }
    }

    /// Looks at a real photo when one has been copied to the app's Documents (not part of the normal run).
    @Test(.enabled(if: DiffusionTests.modelDir != nil && FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Documents/sd_input.jpg"))) func fillsAHoleInARealPhoto() throws {
        guard DiffusionInpainter.hasRoom else { return }
        let docs = URL(fileURLWithPath: NSHomeDirectory() + "/Documents")
        let photo = try #require(CIImage(contentsOf: docs.appendingPathComponent("sd_input.jpg")))
        let e = photo.extent
        let disc = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(x: e.midX, y: e.midY * 0.8), "inputRadius0": 60, "inputRadius1": 61, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!.cropped(to: e)
        let out = try DiffusionInpainter(directory: DiffusionTests.modelDir!, steps: 25, guidance: 4).inpaint(photo, mask: disc)
        let lama = try LaMaInpainter().inpaint(photo, mask: disc)
        let ctx = CIContext()
        for (name, img) in [("sd_real_out.png", out), ("sd_real_lama.png", lama)] {
            try ctx.pngRepresentation(of: img, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)?.write(to: docs.appendingPathComponent(name))
        }
        #expect(out.extent == e)
    }
}
