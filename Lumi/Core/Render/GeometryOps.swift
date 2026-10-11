import CoreImage
import Foundation

struct CropSpec: Codable, Equatable {
    /// Normalized crop rect, origin top-left, applied after rotation/flip.
    var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var quarterTurns = 0          // clockwise 90° steps, 0...3
    var angle = 0.0               // free rotation in degrees, clockwise, -45...45
    var flipH = false
    var flipV = false

    var isIdentity: Bool { self == CropSpec() }

    static let ratios: [(name: String, w: Double, h: Double)] = [
        ("1:1", 1, 1), ("4:3", 4, 3), ("3:4", 3, 4), ("16:9", 16, 9), ("9:16", 9, 16),
        ("3:2", 3, 2), ("2:3", 2, 3), ("4:5", 4, 5), ("5:7", 5, 7),
    ]

    /// Largest centered rect of aspect `w:h` inside an image of `size`, normalized.
    static func rect(aspect w: Double, _ h: Double, in size: CGSize) -> CGRect {
        guard w > 0, h > 0, size.width > 0, size.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let target = w / h, have = Double(size.width / size.height)
        let nw = have > target ? target / have : 1, nh = have > target ? 1 : have / target
        return CGRect(x: (1 - nw) / 2, y: (1 - nh) / 2, width: nw, height: nh)
    }

    /// Rotation that levels a horizon measured at `tilt` degrees (clockwise-positive); clamped to the control range.
    static func straighten(horizonTilt tilt: Double) -> Double { min(max(-tilt, -45), 45) }
}

enum GeometryOps {
    static func apply(_ spec: CropSpec, to image: CIImage) -> CIImage {
        guard !spec.isIdentity else { return image }
        var img = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

        if spec.flipH { img = flip(img, horizontal: true) }
        if spec.flipV { img = flip(img, horizontal: false) }

        for _ in 0..<(((spec.quarterTurns % 4) + 4) % 4) {
            // clockwise in a y-up space is -90°
            img = img.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2))
            img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
        }

        if spec.angle != 0 { img = rotateCropped(img, degrees: spec.angle) }

        let e = img.extent
        let r = spec.rect
        let crop = CGRect(x: e.minX + r.minX * e.width,
                          y: e.minY + (1 - r.maxY) * e.height,       // CI is bottom-left origin
                          width: r.width * e.width, height: r.height * e.height).integral
        let out = img.cropped(to: crop.intersection(e))
        return out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
    }

    private static func flip(_ img: CIImage, horizontal: Bool) -> CIImage {
        let e = img.extent
        let t = horizontal ? CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -e.width, y: 0)
                           : CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -e.height)
        return img.transformed(by: t)
    }

    /// Rotates about the center and crops to the largest axis-aligned rect that stays inside the original frame.
    static func rotateCropped(_ img: CIImage, degrees: Double) -> CIImage {
        let e = img.extent
        let rad = -degrees * .pi / 180   // clockwise-positive
        let c = CGPoint(x: e.midX, y: e.midY)
        let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: rad).translatedBy(x: -c.x, y: -c.y)
        let (w, h) = insetSize(width: e.width, height: e.height, radians: abs(rad))
        let rotated = img.transformed(by: t)
        let box = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
        return rotated.cropped(to: box)
    }

    /// Largest same-aspect rect that fits inside a w×h frame rotated by `radians`.
    static func insetSize(width w: CGFloat, height h: CGFloat, radians a: CGFloat) -> (CGFloat, CGFloat) {
        guard w > 0, h > 0 else { return (0, 0) }
        let s = abs(sin(a)), c = abs(cos(a))
        let scale = 1 / (c + s * max(w / h, h / w))
        return (w * scale, h * scale)
    }
}
