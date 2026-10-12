import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

struct AdjustParams: Codable, Equatable {
    var brightness = 0.0      // -1...1
    var contrast = 0.0        // -1...1
    var saturation = 0.0      // -1...1
    var vibrance = 0.0        // -1...1
    var temperature = 0.0     // -1...1 (cool ... warm)
    var tint = 0.0            // -1...1
    var highlights = 0.0      // -1...1
    var shadows = 0.0         // -1...1
    var sharpen = 0.0         // 0...1
    var vignette = 0.0        // 0...1
    var fade = 0.0            // 0...1

    var isIdentity: Bool { self == AdjustParams() }

    enum Key: String, CaseIterable, Codable { case brightness, contrast, saturation, vibrance, temperature, tint, highlights, shadows, sharpen, vignette, fade }

    subscript(key: Key) -> Double {
        get {
            switch key {
            case .brightness: brightness; case .contrast: contrast; case .saturation: saturation; case .vibrance: vibrance
            case .temperature: temperature; case .tint: tint; case .highlights: highlights; case .shadows: shadows
            case .sharpen: sharpen; case .vignette: vignette; case .fade: fade
            }
        }
        set {
            let v = min(max(newValue, key.range.lowerBound), key.range.upperBound)
            switch key {
            case .brightness: brightness = v; case .contrast: contrast = v; case .saturation: saturation = v; case .vibrance: vibrance = v
            case .temperature: temperature = v; case .tint: tint = v; case .highlights: highlights = v; case .shadows: shadows = v
            case .sharpen: sharpen = v; case .vignette: vignette = v; case .fade: fade = v
            }
        }
    }

    mutating func reset(_ key: Key) { self[key] = 0 }

    static let presets: [String: AdjustParams] = [
        "warm": AdjustParams(temperature: 0.4, tint: 0.05),
        "cool": AdjustParams(temperature: -0.4),
        "vivid": AdjustParams(contrast: 0.15, saturation: 0.25, vibrance: 0.3),
    ]
}

extension AdjustParams.Key {
    var range: ClosedRange<Double> { [.sharpen, .vignette, .fade].contains(self) ? 0...1 : -1...1 }
}

enum AdjustOps {
    static func apply(_ p: AdjustParams, to image: CIImage) -> CIImage {
        guard !p.isIdentity else { return image }
        var img = image

        if p.brightness != 0 {
            // a midtone lift with black and white pinned: brighter without the washed-out look an additive offset gives
            let b = p.brightness
            let f = CIFilter.toneCurve()
            f.inputImage = img
            f.point0 = CGPoint(x: 0, y: 0)
            f.point1 = CGPoint(x: 0.25, y: 0.25 + 0.12 * b)
            f.point2 = CGPoint(x: 0.5, y: 0.5 + 0.2 * b)
            f.point3 = CGPoint(x: 0.75, y: 0.75 + 0.12 * b)
            f.point4 = CGPoint(x: 1, y: 1)
            img = f.outputImage ?? img
        }
        if p.contrast != 0 || p.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.contrast = Float(1 + p.contrast * 0.5)
            f.saturation = Float(1 + p.saturation)
            img = f.outputImage ?? img
        }
        if p.vibrance != 0 {
            let f = CIFilter.vibrance(); f.inputImage = img; f.amount = Float(p.vibrance)
            img = f.outputImage ?? img
        }
        if p.temperature != 0 || p.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - p.temperature * 2500, y: p.tint * 100)
            img = f.outputImage ?? img
        }
        if p.highlights != 0 || p.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = img
            f.highlightAmount = Float(1 + p.highlights)    // <1 recovers highlights
            f.shadowAmount = Float(p.shadows)
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
        return img.cropped(to: image.extent)
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
