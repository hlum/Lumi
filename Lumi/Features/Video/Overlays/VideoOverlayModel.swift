import CoreGraphics
import CoreImage
import Foundation

/// A text or sticker shown on the video between `start` and `end` (seconds on the timeline).
struct VideoOverlay: Codable, Equatable, Identifiable {
    enum Content: Codable, Equatable { case text(String), sticker(String) }
    enum Animation: String, Codable, CaseIterable { case none, fade, pop, slideUp, slideDown, slideLeft, slideRight }

    var id = UUID()
    var content: Content
    var start: Double
    var end: Double
    var keyframes = Keyframes()
    var animationIn = Animation.none
    var animationOut = Animation.none
    var animationDuration = 0.4

    func isActive(at t: Double) -> Bool { t >= start && t < end }
}

enum OverlayTimeline {
    /// Pose of an overlay at timeline time `t`: keyframes (times relative to `start`), then the in/out animation on top.
    static func pose(_ o: VideoOverlay, at t: Double, base: Keyframes.Pose = .init(x: 0.5, y: 0.5, scale: 1, rotation: 0, opacity: 1)) -> Keyframes.Pose? {
        guard o.isActive(at: t) else { return nil }
        var p = o.keyframes.pose(at: t - o.start, base: base)
        let d = max(min(o.animationDuration, (o.end - o.start) / 2), 0.0001)
        let tin = (t - o.start) / d, tout = (o.end - t) / d
        if tin < 1 && o.animationIn != .none { apply(o.animationIn, progress: min(max(tin, 0), 1), entering: true, to: &p) }
        if tout < 1 && o.animationOut != .none { apply(o.animationOut, progress: min(max(tout, 0), 1), entering: false, to: &p) }
        return p
    }

    /// `progress` 0 = hidden/offscreen, 1 = rest pose.
    private static func apply(_ a: VideoOverlay.Animation, progress u: Double, entering: Bool, to p: inout Keyframes.Pose) {
        let e = Track.curve(entering ? .easeOut : .easeIn, u), off = (1 - e) * 0.3
        switch a {
        case .none: break
        case .fade: p.opacity *= e
        case .pop: p.scale *= e; p.opacity *= min(1, e * 2)
        case .slideUp: p.y += off; p.opacity *= e
        case .slideDown: p.y -= off; p.opacity *= e
        case .slideLeft: p.x += off; p.opacity *= e
        case .slideRight: p.x -= off; p.opacity *= e
        }
    }

    static func active(_ overlays: [VideoOverlay], at t: Double) -> [VideoOverlay] { overlays.filter { $0.isActive(at: t) } }

    /// Draws `content` (already rendered, e.g. text or sticker image) onto `frame` at the pose for time `t`.
    static func draw(_ content: CIImage, pose p: Keyframes.Pose, on frame: CIImage) -> CIImage {
        let e = frame.extent, c = content.extent
        guard p.opacity > 0, c.width > 0 else { return frame }
        let t = CGAffineTransform(translationX: -c.midX, y: -c.midY).concatenating(CGAffineTransform(scaleX: p.scale, y: p.scale))
            .concatenating(CGAffineTransform(rotationAngle: -p.rotation))
            .concatenating(CGAffineTransform(translationX: e.minX + p.x * e.width, y: e.minY + (1 - p.y) * e.height))
        let layer = content.transformed(by: t).applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: p.opacity)])
        return layer.composited(over: frame).cropped(to: e)
    }
}
