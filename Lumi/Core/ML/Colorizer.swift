import CoreImage
import CoreML
import Foundation

protocol Colorizing { func colorize(_ image: CIImage) throws -> CIImage }

enum ColorizeError: Error, Equatable { case modelMissing, tooLarge, bufferFailed, predictionFailed }

/// Pure Lab helpers so the model's output can be merged with the photo's own full-resolution lightness.
enum LabMerge {
    /// L in 0...100 from sRGB bytes (BGRA or RGBA, `r`,`g`,`b` indices given).
    static func lightness(r: UInt8, g: UInt8, b: UInt8) -> Double { ColorTransfer.lab(Double(r) / 255, Double(g) / 255, Double(b) / 255)[0] }

    /// Bilinear sample of a 2-channel plane (`side` x `side`) at normalized (u, v) in 0...1.
    static func sample(_ plane: [Float], side: Int, channel: Int, u: Double, v: Double) -> Float {
        let x = min(max(u, 0), 1) * Double(side - 1), y = min(max(v, 0), 1) * Double(side - 1)
        let x0 = Int(x), y0 = Int(y), x1 = min(x0 + 1, side - 1), y1 = min(y0 + 1, side - 1)
        let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
        func at(_ xx: Int, _ yy: Int) -> Float { plane[channel * side * side + yy * side + xx] }
        let top = at(x0, y0) * (1 - fx) + at(x1, y0) * fx, bot = at(x0, y1) * (1 - fx) + at(x1, y1) * fx
        return top * (1 - fy) + bot * fy
    }
}

/// SIGGRAPH 2017 colorization (BSD) on Core ML: the net predicts color from lightness at 512x512,
/// then the colors are applied to the photo's own lightness at full resolution so detail stays sharp.
final class SiggraphColorizer: Colorizing {
    static let side = 512
    static let maxInputSide = 2048
    private let model: MLModel
    private let context = CIContext()

    static var isModelAvailable: Bool { Bundle.main.url(forResource: "SIGGraph17Colorizer", withExtension: "mlmodelc") != nil }

    init() throws {
        guard let url = Bundle.main.url(forResource: "SIGGraph17Colorizer", withExtension: "mlmodelc") else { throw ColorizeError.modelMissing }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: cfg)
    }

    /// Runs the network on a lightness plane (0...100, side x side) and returns [a plane | b plane] (each side*side).
    func predictAB(lightness: [Float]) throws -> [Float] {
        let n = Self.side
        guard lightness.count == n * n else { throw ColorizeError.bufferFailed }
        let input = try MLMultiArray(shape: [1, 1, NSNumber(value: n), NSNumber(value: n)], dataType: .float32)
        for i in 0..<(n * n) { input[i] = NSNumber(value: lightness[i]) }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input1": MLFeatureValue(multiArray: input)]))
        guard let arr = out.featureValue(for: "var_518")?.multiArrayValue, arr.count == 2 * n * n else { throw ColorizeError.predictionFailed }
        return (0..<arr.count).map { arr[$0].floatValue }
    }

    func colorize(_ image: CIImage) throws -> CIImage {
        let e = image.extent
        guard max(e.width, e.height) <= CGFloat(Self.maxInputSide) else { throw ColorizeError.tooLarge }
        let w = Int(e.width), h = Int(e.height), n = Self.side
        let base = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        // full-resolution pixels (RGBA8, top row first)
        var full = [UInt8](repeating: 0, count: w * h * 4)
        context.render(base, toBitmap: &full, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        // 512x512 lightness for the network
        var small = [UInt8](repeating: 0, count: n * n * 4)
        context.render(base.transformed(by: CGAffineTransform(scaleX: CGFloat(n) / e.width, y: CGFloat(n) / e.height)), toBitmap: &small, rowBytes: n * 4, bounds: CGRect(x: 0, y: 0, width: n, height: n), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let L = (0..<(n * n)).map { Float(LabMerge.lightness(r: small[$0 * 4], g: small[$0 * 4 + 1], b: small[$0 * 4 + 2])) }
        let ab = try predictAB(lightness: L)

        var out = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let v = h > 1 ? Double(y) / Double(h - 1) : 0
            for x in 0..<w {
                let i = (y * w + x) * 4
                let u = w > 1 ? Double(x) / Double(w - 1) : 0
                let l = LabMerge.lightness(r: full[i], g: full[i + 1], b: full[i + 2])
                let a = Double(LabMerge.sample(ab, side: n, channel: 0, u: u, v: v)), b = Double(LabMerge.sample(ab, side: n, channel: 1, u: u, v: v))
                let rgb = ColorTransfer.rgb(fromLab: l, a, b)
                out[i] = UInt8((rgb.0 * 255).rounded()); out[i + 1] = UInt8((rgb.1 * 255).rounded()); out[i + 2] = UInt8((rgb.2 * 255).rounded())
            }
        }
        let provider = CGDataProvider(data: Data(out) as CFData)!
        guard let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw ColorizeError.bufferFailed }
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY))
    }
}

final class LazyColorizer: Colorizing {
    private var real: SiggraphColorizer?
    func colorize(_ image: CIImage) throws -> CIImage {
        if real == nil { real = try SiggraphColorizer() }
        return try real!.colorize(image)
    }
}
