import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

struct AdjustParams: Codable, Equatable {
    var exposure = 0.0        // -1...1  = -2...+2 EV, a gain on linear light
    var brightness = 0.0      // -1...1  midtone lift, black and white stay put
    var contrast = 0.0        // -1...1  S-curve around mid grey
    var highlights = 0.0      // -1...1
    var shadows = 0.0         // -1...1
    var whites = 0.0          // -1...1  moves the white point
    var blacks = 0.0          // -1...1  moves the black point
    var texture = 0.0         // -1...1  fine detail
    var clarity = 0.0         // -1...1  midtone local contrast
    var dehaze = 0.0          // -1...1
    var saturation = 0.0      // -1...1
    var vibrance = 0.0        // -1...1
    var temperature = 0.0     // -1...1 (cool ... warm)
    var tint = 0.0            // -1...1
    var sharpen = 0.0         // 0...1
    var vignette = 0.0        // 0...1
    var fade = 0.0            // 0...1
    var grain = 0.0           // 0...1

    var isIdentity: Bool { self == AdjustParams() }

    enum Key: String, CaseIterable, Codable {
        case exposure, brightness, contrast, highlights, shadows, whites, blacks, texture, clarity, dehaze, saturation, vibrance, temperature, tint, sharpen, vignette, fade, grain
        var path: WritableKeyPath<AdjustParams, Double> {
            switch self {
            case .exposure: \.exposure; case .brightness: \.brightness; case .contrast: \.contrast; case .highlights: \.highlights; case .shadows: \.shadows
            case .whites: \.whites; case .blacks: \.blacks; case .texture: \.texture; case .clarity: \.clarity; case .dehaze: \.dehaze
            case .saturation: \.saturation; case .vibrance: \.vibrance; case .temperature: \.temperature; case .tint: \.tint
            case .sharpen: \.sharpen; case .vignette: \.vignette; case .fade: \.fade; case .grain: \.grain
            }
        }
    }

    subscript(key: Key) -> Double {
        get { self[keyPath: key.path] }
        set { self[keyPath: key.path] = min(max(newValue, key.range.lowerBound), key.range.upperBound) }
    }

    mutating func reset(_ key: Key) { self[key] = 0 }

    static let presets: [String: AdjustParams] = [
        "warm": AdjustParams(temperature: 0.4, tint: 0.05),
        "cool": AdjustParams(temperature: -0.4),
        "vivid": AdjustParams(contrast: 0.15, saturation: 0.25, vibrance: 0.3),
        "crisp": AdjustParams(contrast: 0.2, texture: 0.3, clarity: 0.25),
        "soft": AdjustParams(contrast: -0.15, clarity: -0.3, fade: 0.2),
        "hdr": AdjustParams(highlights: -0.5, shadows: 0.5, clarity: 0.4, dehaze: 0.2, vibrance: 0.2),
    ]
}

extension AdjustParams {
    /// Old drafts have fewer fields; anything missing stays at 0.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        self.init()
        for k in Key.allCases { if let v = try c.decodeIfPresent(Double.self, forKey: DynamicKey(k.rawValue)) { self[keyPath: k.path] = v } }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        for k in Key.allCases { try c.encode(self[keyPath: k.path], forKey: DynamicKey(k.rawValue)) }
    }
    private struct DynamicKey: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

extension AdjustParams.Key {
    var range: ClosedRange<Double> { [.sharpen, .vignette, .fade, .grain].contains(self) ? 0...1 : -1...1 }
}

/// Lightroom-style order: white balance, exposure, tone, detail, colour, finishing. Tone work happens in gamma space
/// (how the picture looks), exposure and white balance in linear light (how light adds up).
enum AdjustOps {
    static func apply(_ p: AdjustParams, to image: CIImage) -> CIImage {
        guard !p.isIdentity else { return image }
        let e = image.extent
        var img = image

        if p.temperature != 0 || p.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - p.temperature * 2500, y: -p.tint * 100)       // + tint = magenta, like other editors
            img = f.outputImage ?? img
        }
        if p.exposure != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = img; f.ev = Float(p.exposure * 2)
            img = f.outputImage ?? img
        }

        // brightness, contrast and blacks are all "map each tone to another tone": one lookup, applied as the picture looks (sRGB)
        let shape = tonalShape(p)
        if !shape.isIdentity { img = curved(img, shape) }

        let toneTouched = p.highlights != 0 || p.shadows != 0 || p.whites != 0
        let detailTouched = p.texture != 0 || p.clarity != 0 || p.dehaze != 0
        if toneTouched || detailTouched || p.saturation != 0 {
            img = gamma(img) { g in
                var o = g
                if p.highlights != 0 || p.shadows != 0 {
                    let f = CIFilter.highlightShadowAdjust()
                    f.inputImage = o; f.highlightAmount = Float(1 - p.highlights); f.shadowAmount = Float(p.shadows)
                    o = f.outputImage?.cropped(to: e) ?? o
                }
                if p.whites != 0 {      // white point: a gain that mostly moves the top
                    let k = CGFloat(1 + 0.25 * p.whites)
                    o = o.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)])
                }
                if p.dehaze != 0 { o = dehaze(o, p.dehaze) }
                if p.clarity != 0 { o = localContrast(o, amount: p.clarity, radius: max(e.width, e.height) * 0.02, midtonesOnly: true) }
                if p.texture != 0 { o = localContrast(o, amount: p.texture, radius: max(e.width, e.height) * 0.003, midtonesOnly: false) }
                return o
            }
        }
        if p.saturation != 0 {
            let f = CIFilter.colorControls(); f.inputImage = img; f.saturation = Float(1 + p.saturation)
            img = f.outputImage ?? img
        }
        if p.vibrance != 0 {
            let f = CIFilter.vibrance(); f.inputImage = img; f.amount = Float(p.vibrance)
            img = f.outputImage ?? img
        }
        if p.fade != 0 {
            let f = CIFilter.colorMatrix()
            f.inputImage = img
            let lift = CGFloat(p.fade * 0.15), k = 1 - lift
            f.rVector = CIVector(x: k, y: 0, z: 0, w: 0); f.gVector = CIVector(x: 0, y: k, z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: k, w: 0); f.biasVector = CIVector(x: lift, y: lift, z: lift, w: 0)
            img = f.outputImage ?? img
        }
        if p.sharpen != 0 {
            let f = CIFilter.sharpenLuminance(); f.inputImage = img; f.sharpness = Float(p.sharpen * 1.5)
            img = f.outputImage ?? img
        }
        if p.vignette != 0 {
            let f = CIFilter.vignette(); f.inputImage = img; f.intensity = Float(p.vignette * 2); f.radius = 2
            img = f.outputImage ?? img
        }
        if p.grain > 0 { img = grain(img, amount: p.grain) }
        return img.cropped(to: e)
    }

    // MARK: building blocks

    /// Runs `body` on the picture as it looks (sRGB-encoded) and returns it to linear light.
    static func gamma(_ image: CIImage, _ body: (CIImage) -> CIImage) -> CIImage {
        body(image.applyingFilter("CILinearToSRGBToneCurve")).applyingFilter("CISRGBToneCurveToLinear").cropped(to: image.extent)
    }

    /// Brightness, contrast and blacks as one tone curve (x and y are how bright a tone looks, 0...1).
    static func tonalShape(_ p: AdjustParams) -> ToneCurve {
        guard p.brightness != 0 || p.contrast != 0 || p.blacks != 0 else { return ToneCurve() }
        let bright = ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.25 + 0.12 * p.brightness), CGPoint(x: 0.5, y: 0.5 + 0.2 * p.brightness), CGPoint(x: 0.75, y: 0.75 + 0.12 * p.brightness), CGPoint(x: 1, y: 1)])
        let contrast = ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.25 - 0.09 * p.contrast), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.75, y: 0.75 + 0.09 * p.contrast), CGPoint(x: 1, y: 1)])
        // blacks: + lifts the darkest tones, - crushes them
        let blacks = ToneCurve(points: [CGPoint(x: 0, y: max(p.blacks, 0) * 0.12), CGPoint(x: 0.25, y: 0.25 + p.blacks * 0.05), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.75, y: 0.75), CGPoint(x: 1, y: 1)])
        let samples = (0..<65).map { i -> CGPoint in
            let x = Double(i) / 64
            return CGPoint(x: x, y: blacks.value(at: contrast.value(at: bright.value(at: x))))
        }
        return ToneCurve(points: samples)
    }

    /// Applies a curve to how the picture looks: Core Image converts to sRGB, runs the lookup, and converts back.
    static func curved(_ image: CIImage, _ c: ToneCurve) -> CIImage {
        guard !c.isIdentity, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        var floats: [Float] = []
        for i in 0..<256 { let y = Float(c.value(at: Double(i) / 255)); floats += [y, y, y] }
        let data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let f = CIFilter(name: "CIColorCurves", parameters: [kCIInputImageKey: image, "inputCurvesData": data, "inputCurvesDomain": CIVector(x: 0, y: 1), "inputColorSpace": space])
        return f?.outputImage?.cropped(to: image.extent) ?? image
    }

    /// Unsharp mask on a wide (clarity) or narrow (texture) radius. Negative amounts blur toward the soft version instead.
    /// Clarity is weighted to the midtones so it does not grind the darkest and brightest areas.
    static func localContrast(_ image: CIImage, amount: Double, radius: Double, midtonesOnly: Bool) -> CIImage {
        let e = image.extent
        let r = max(radius, 1.5)
        let result: CIImage
        if amount > 0 {
            let f = CIFilter.unsharpMask(); f.inputImage = image; f.radius = Float(r); f.intensity = Float(amount * (midtonesOnly ? 0.9 : 1.2))
            result = f.outputImage?.cropped(to: e) ?? image
        } else {
            let soft = image.clampedToExtent().applyingGaussianBlur(sigma: r * 0.5).cropped(to: e)
            result = CIFilter(name: "CIDissolveTransition", parameters: [kCIInputImageKey: image, kCIInputTargetImageKey: soft, kCIInputTimeKey: min(-amount, 1) * 0.7])?.outputImage?.cropped(to: e) ?? image
        }
        guard midtonesOnly else { return result }
        // weight: 1 at mid grey, 0.25 at pure black and white
        let luma = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        let dist = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: e).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: luma])      // |l - 0.5|
        let weight = dist.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: -1.5, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: -1.5, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: -1.5, w: 0), "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)])
        let f = CIFilter.blendWithMask(); f.inputImage = result; f.backgroundImage = image; f.maskImage = weight
        return f.outputImage?.cropped(to: e) ?? result
    }

    /// Positive: removes haze using the dark-channel estimate (the darkest colour channel in a neighbourhood shows how much
    /// veil sits over the scene). Negative: adds a soft veil.
    static func dehaze(_ image: CIImage, _ amount: Double) -> CIImage {
        let e = image.extent
        if amount < 0 {
            let a = CGFloat(-amount * 0.35)
            return image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1 - a, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1 - a, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1 - a, w: 0), "inputBiasVector": CIVector(x: 0.7 * a, y: 0.7 * a, z: 0.7 * a, w: 0)])
        }
        let radius = max(e.width, e.height) * 0.01
        let dark = image.applyingFilter("CIMinimumComponent").clampedToExtent().applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius]).applyingGaussianBlur(sigma: radius).cropped(to: e)
        let k = CGFloat(min(amount, 1) * 0.9)
        let veil = dark.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0)])
        // J = (I - veil) / (1 - veil)
        let removed = veil.applyingFilter("CISubtractBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)       // background - input
        let denom = veil.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: -1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: -1, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: -1, w: 0), "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)])
        return denom.applyingFilter("CIDivideBlendMode", parameters: [kCIInputBackgroundImageKey: removed]).cropped(to: e)
    }

    /// Film-like luminance noise, soft-light blended; scaled to the picture so it looks the same at any size.
    static func grain(_ image: CIImage, amount: Double) -> CIImage {
        let e = image.extent
        let size = max(e.width, e.height)
        let scale = max(size / 1500, 1)                                  // grain keeps its look on big photos
        let noise = (CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage())
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.2])
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: e)
        let weak = noise.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(amount, 1)))])
        return weak.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: e)
    }

    static func apply(_ c: ToneCurve, to image: CIImage) -> CIImage {
        guard !c.isIdentity else { return image }
        let f = CIFilter.toneCurve()
        f.inputImage = image
        let xs: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        let ys = xs.map { CGFloat(c.value(at: Double($0))) }
        f.point0 = CGPoint(x: xs[0], y: ys[0]); f.point1 = CGPoint(x: xs[1], y: ys[1]); f.point2 = CGPoint(x: xs[2], y: ys[2])
        f.point3 = CGPoint(x: xs[3], y: ys[3]); f.point4 = CGPoint(x: xs[4], y: ys[4])
        return f.outputImage ?? image
    }
}
