import CoreImage

/// Removes an object from a short clip: the tracked box (grown a little) is inpainted every frame, then blended over time.
struct VideoEraser {
    /// Measured limit is filled in after the device run; until then a conservative cap.
    static let maxSeconds = 8.0
    static let maxFrames = 240

    var track: ObjectTrack
    var grow = 0.25                   // how much larger than the tracked box the erased area is
    var blend = TemporalBlend()

    /// Whether a clip of this length is accepted, and how many frames to process at this frame rate.
    static func plan(duration: Double, fps: Double) -> (accepted: Bool, frames: Int) {
        let n = Int((duration * fps).rounded(.up))
        return (duration > 0 && duration <= maxSeconds && n <= maxFrames, n)
    }

    /// White rectangle over the (grown) box, frame-normalized y-down, on a black canvas of `extent`.
    static func mask(box: CGRect, grow: Double, extent: CGRect) -> CIImage {
        let g = box.insetBy(dx: -box.width * grow / 2, dy: -box.height * grow / 2).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = CGRect(x: extent.minX + g.minX * extent.width, y: extent.minY + (1 - g.maxY) * extent.height, width: g.width * extent.width, height: g.height * extent.height)
        return CIImage(color: .white).cropped(to: r).composited(over: CIImage(color: .black).cropped(to: extent)).cropped(to: extent)
    }

    /// Erases one frame. Frames where the object is lost pass through untouched.
    mutating func process(frame: CIImage, at time: Double, inpainter: Inpainting) throws -> CIImage {
        guard let box = track.box(at: time) else { return frame }
        let m = Self.mask(box: box, grow: grow, extent: frame.extent)
        let filled = try inpainter.inpaint(frame, mask: m)
        return blend.blend(filled: filled, mask: m)
    }
}
