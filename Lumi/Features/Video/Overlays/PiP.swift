import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// A second video (or photo) shown over the main one.
struct PiP: Codable, Equatable {
    enum Blend: String, Codable, CaseIterable { case normal, multiply, screen, overlay, softLight, add }
    enum Shape: String, Codable, CaseIterable { case rect, rounded, circle, heart }

    var center = CGPoint(x: 0.75, y: 0.25)      // frame-normalized, y-down
    var width = 0.35                            // fraction of frame width
    var rotation = 0.0
    var opacity = 1.0
    var blend = Blend.normal
    var shape = Shape.rounded
    var start = 0.0, end = 5.0

    func isActive(at t: Double) -> Bool { t >= start && t < end }

    var filterName: String {
        switch blend {
        case .normal: "CISourceOverCompositing"; case .multiply: "CIMultiplyBlendMode"; case .screen: "CIScreenBlendMode"
        case .overlay: "CIOverlayBlendMode"; case .softLight: "CISoftLightBlendMode"; case .add: "CIAdditionCompositing"
        }
    }
}

enum PiPRenderer {
    /// `overlay` is the PiP source frame at the right moment; `pose` can come from keyframes, or tracking.
    static func draw(_ overlay: CIImage, _ p: PiP, on frame: CIImage, center: CGPoint? = nil) -> CIImage {
        let e = frame.extent, o = overlay.extent
        guard o.width > 0, o.height > 0 else { return frame }
        let w = CGFloat(p.width) * e.width, s = w / o.width, h = o.height * s
        let c = center ?? p.center
        let shaped = Masks.apply(p.shape, to: overlay.transformed(by: CGAffineTransform(translationX: -o.minX, y: -o.minY)))
        let t = CGAffineTransform(translationX: -o.width / 2, y: -o.height / 2).concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(-p.rotation)))
            .concatenating(CGAffineTransform(translationX: e.minX + c.x * e.width, y: e.minY + (1 - c.y) * e.height))
        _ = h
        let placed = shaped.transformed(by: t).applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(min(max(p.opacity, 0), 1)))])
        return placed.applyingFilter(p.filterName, parameters: [kCIInputBackgroundImageKey: frame]).cropped(to: e)
    }
}
