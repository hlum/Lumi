import CoreGraphics
import Foundation

/// Planning for turning a Live Photo's clip into a GIF or video, and a video into a Live Photo.
enum LiveConvert {
    static let liveLength = 3.0           // a Live Photo plays about 3 seconds
    static let maxGIFFrames = 90

    /// Times to sample for a GIF: evenly spaced at `fps`, never more than `maxGIFFrames`.
    static func gifTimes(duration: Double, fps: Double = 10) -> [Double] {
        guard duration > 0, fps > 0 else { return [] }
        let n = min(max(Int((duration * fps).rounded()), 1), maxGIFFrames)
        return (0..<n).map { duration * Double($0) / Double(n) }
    }

    /// The part of a video that becomes a Live Photo: `liveLength` seconds around the key frame,
    /// moved inward when the key frame is near the start or end.
    static func liveWindow(videoDuration: Double, keyTime: Double) -> (start: Double, end: Double, key: Double)? {
        guard videoDuration > 0 else { return nil }
        let len = min(liveLength, videoDuration)
        let key = min(max(keyTime, 0), videoDuration)
        let start = min(max(key - len / 2, 0), videoDuration - len)
        return (start, start + len, key - start)          // key is relative to the window
    }

    /// Slideshow: each photo for `perPhoto` seconds, so the whole show's length and each photo's start time.
    static func slideshow(count: Int, perPhoto: Double = 1.0) -> (duration: Double, starts: [Double]) {
        guard count > 0, perPhoto > 0 else { return (0, []) }
        return (Double(count) * perPhoto, (0..<count).map { Double($0) * perPhoto })
    }
}
