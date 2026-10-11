import CoreImage
import CoreML
import Foundation

protocol Upscaling { func upscale4x(_ image: CIImage) throws -> CIImage }

enum UpscaleError: Error, Equatable { case modelMissing, tooLarge, bufferFailed, predictionFailed }

enum TilePlan {
    static let tile = 512

    struct Tile: Equatable { var origin: CGPoint; var core: CGRect }   // core: the part of the image this tile is responsible for

    /// Evenly spaced window origins; every pair of neighbours overlaps by at least `overlap` px.
    private static func origins(_ length: Int, overlap: Int) -> [Int] {
        guard length > tile else { return [0] }
        let n = Int((Double(length - overlap) / Double(tile - overlap)).rounded(.up))
        guard n > 1 else { return [0] }
        return (0..<n).map { Int((Double($0) * Double(length - tile) / Double(n - 1)).rounded()) }
    }

    /// Windows of `tile` px with `overlap` px shared. Cores partition the image exactly (seams at the middle of each overlap).
    static func tiles(width: Int, height: Int, overlap: Int = 32) -> [Tile] {
        guard width > 0, height > 0 else { return [] }
        let xs = origins(width, overlap: overlap), ys = origins(height, overlap: overlap)
        func bounds(_ o: [Int], _ i: Int, _ length: Int) -> (Int, Int) {
            let lo = i == 0 ? 0 : (o[i] + o[i - 1] + tile) / 2
            let hi = i == o.count - 1 ? length : (o[i + 1] + o[i] + tile) / 2
            return (lo, hi)
        }
        var out: [Tile] = []
        for (j, y) in ys.enumerated() { for (i, x) in xs.enumerated() {
            let (x0, x1) = bounds(xs, i, width), (y0, y1) = bounds(ys, j, height)
            out.append(Tile(origin: CGPoint(x: x, y: y), core: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)))
        } }
        return out
    }
}

/// Real-ESRGAN x4 (BSD-3-Clause) on Core ML, run tile by tile.
final class RealESRGANUpscaler: Upscaling {
    static let maxInputSide = 2048
    private let model: MLModel
    private let context = CIContext()

    static var isModelAvailable: Bool { Bundle.main.url(forResource: "RealESRGAN_x4", withExtension: "mlmodelc") != nil }

    init() throws {
        guard let url = Bundle.main.url(forResource: "RealESRGAN_x4", withExtension: "mlmodelc") else { throw UpscaleError.modelMissing }
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: cfg)
    }

    func upscale4x(_ image: CIImage) throws -> CIImage {
        let e = image.extent
        guard max(e.width, e.height) <= CGFloat(Self.maxInputSide) else { throw UpscaleError.tooLarge }
        let w = Int(e.width), h = Int(e.height)
        let src = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)).clampedToExtent()     // edge pixels repeat into padding
        var canvas = CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: w * 4, height: h * 4))
        for t in TilePlan.tiles(width: w, height: h) {
            // CI is bottom-left; tile origins are top-left
            let ciY = CGFloat(h) - t.origin.y - CGFloat(TilePlan.tile)
            let window = src.cropped(to: CGRect(x: t.origin.x, y: ciY, width: CGFloat(TilePlan.tile), height: CGFloat(TilePlan.tile)))
                .transformed(by: CGAffineTransform(translationX: -t.origin.x, y: -ciY))
            let input = try buffer(window, side: TilePlan.tile)
            let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(pixelBuffer: input)]))
            guard let ob = out.featureValue(for: "activation_out")?.imageBufferValue else { throw UpscaleError.predictionFailed }
            // keep only this tile's core, placed at 4x
            let coreCI = CGRect(x: t.core.minX, y: CGFloat(h) - t.core.maxY, width: t.core.width, height: t.core.height)
            let local = CGRect(x: (coreCI.minX - t.origin.x) * 4, y: (coreCI.minY - ciY) * 4, width: coreCI.width * 4, height: coreCI.height * 4)
            let piece = CIImage(cvPixelBuffer: ob).cropped(to: local)
                .transformed(by: CGAffineTransform(translationX: -local.minX + coreCI.minX * 4, y: -local.minY + coreCI.minY * 4))
            // materialize so the 16 MB output buffer can be reused by the next prediction
            guard let cg = context.createCGImage(piece, from: piece.extent) else { throw UpscaleError.bufferFailed }
            canvas = CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: piece.extent.minX, y: piece.extent.minY)).composited(over: canvas)
        }
        return canvas.cropped(to: CGRect(x: 0, y: 0, width: w * 4, height: h * 4)).transformed(by: CGAffineTransform(translationX: e.minX * 4, y: e.minY * 4))
    }

    private func buffer(_ img: CIImage, side: Int) throws -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb) == kCVReturnSuccess, let pb else { throw UpscaleError.bufferFailed }
        context.render(img, to: pb, bounds: CGRect(x: 0, y: 0, width: side, height: side), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return pb
    }
}

final class LazyUpscaler: Upscaling {
    private var real: RealESRGANUpscaler?
    func upscale4x(_ image: CIImage) throws -> CIImage {
        if real == nil { real = try RealESRGANUpscaler() }
        return try real!.upscale4x(image)
    }
}
