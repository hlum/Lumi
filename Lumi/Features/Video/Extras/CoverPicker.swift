import AVFoundation
import CoreImage

/// Cover = one frame of the video plus a crop to the wanted aspect.
struct VideoCover: Codable, Equatable {
    var time = 0.0
    var aspect = 1.0                 // w/h of the cover; 0.75 for a 3:4 feed tile
    var zoom = 1.0
    var pan = CGPoint.zero

    /// Candidate times spread over the video, skipping the very first and last frames (often black).
    static func candidates(duration: Double, count: Int = 8) -> [Double] {
        guard duration > 0, count > 0 else { return [] }
        return (0..<count).map { duration * (Double($0) + 0.5) / Double(count) }
    }

    func clampedTime(duration: Double) -> Double { min(max(time, 0), max(duration - 0.05, 0)) }

    func crop(_ frame: CIImage) -> CIImage {
        let e = frame.extent
        let c = CollageMath.sourceCrop(image: e.size, slotAspect: aspect, zoom: zoom, pan: pan)
        guard c.width > 0 else { return frame }
        let ci = CGRect(x: e.minX + c.minX, y: e.minY + e.height - c.maxY, width: c.width, height: c.height)
        return frame.cropped(to: ci).transformed(by: CGAffineTransform(translationX: -ci.minX, y: -ci.minY))
    }

    /// Extracts the frame at the chosen time and crops it.
    func render(from asset: AVAsset) async throws -> CIImage {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let d = try await asset.load(.duration).seconds
        let cg = try await gen.image(at: CMTime(seconds: clampedTime(duration: d), preferredTimescale: 600)).image
        return crop(CIImage(cgImage: cg))
    }
}
