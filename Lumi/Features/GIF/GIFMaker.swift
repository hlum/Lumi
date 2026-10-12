import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GIFMaker {
    struct Options: Equatable {
        var fps = 10.0
        var maxSide = 480
        var loopCount = 0           // 0 = forever
    }

    /// Frames in play order: forward, or forward then back without repeating the end frames (bounce).
    static func sequence<T>(_ frames: [T], bounce: Bool) -> [T] {
        guard bounce, frames.count > 2 else { return frames }
        return frames + frames.dropFirst().dropLast().reversed()
    }

    /// Longest side limited to `maxSide`, never upscaled.
    static func targetSize(for size: CGSize, maxSide: Int) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > CGFloat(maxSide), longest > 0 else { return size }
        let s = CGFloat(maxSide) / longest
        return CGSize(width: (size.width * s).rounded(), height: (size.height * s).rounded())
    }

    static func encode(_ frames: [CGImage], options o: Options = Options()) -> Data? {
        guard !frames.isEmpty, o.fps > 0, o.fps <= 60 else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else { return nil }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: o.loopCount]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / o.fps]] as CFDictionary
        let ctx = CIContext()
        for f in frames {
            let size = targetSize(for: CGSize(width: f.width, height: f.height), maxSide: o.maxSide)
            let img: CGImage
            if size.width == CGFloat(f.width) { img = f } else {
                let ci = CIImage(cgImage: f).transformed(by: CGAffineTransform(scaleX: size.width / CGFloat(f.width), y: size.height / CGFloat(f.height)))
                guard let scaled = ctx.createCGImage(ci, from: CGRect(origin: .zero, size: size)) else { return nil }
                img = scaled
            }
            CGImageDestinationAddImage(dest, img, frameProps)
        }
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    /// Emoji/sticker: the cutout fitted into a transparent square, with a margin.
    static func emoji(_ cutout: CIImage, side: Int = 512, margin: Double = 0.06) -> CIImage {
        let e = cutout.extent
        let box = Double(side) * (1 - 2 * margin)
        let s = min(box / Double(e.width), box / Double(e.height))
        let scaled = cutout.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY)).transformed(by: CGAffineTransform(scaleX: s, y: s))
        let placed = scaled.transformed(by: CGAffineTransform(translationX: (Double(side) - scaled.extent.width) / 2, y: (Double(side) - scaled.extent.height) / 2))
        return placed.composited(over: CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }
}
