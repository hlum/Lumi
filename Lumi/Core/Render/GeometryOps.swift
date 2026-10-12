import CoreImage
import Foundation

struct CropSpec: Codable, Equatable {
    /// Normalized crop rect, origin top-left, applied after rotation/flip.
    var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var quarterTurns = 0          // clockwise 90° steps, 0...3
    var angle = 0.0               // free rotation in degrees, clockwise, -45...45
    var flipH = false
    var flipV = false
    var keystoneV = 0.0           // -1...1 leaning verticals (shot from below or above)
    var keystoneH = 0.0           // -1...1 converging horizontals (shot from the side)

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

extension CropSpec {
    /// Old drafts have no keystone; anything missing stays at its default.
    init(from decoder: Decoder) throws {
        enum K: String, CodingKey { case rect, quarterTurns, angle, flipH, flipV, keystoneV, keystoneH }
        let c = try decoder.container(keyedBy: K.self)
        self.init()
        rect = try c.decodeIfPresent(CGRect.self, forKey: .rect) ?? rect
        quarterTurns = try c.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0
        angle = try c.decodeIfPresent(Double.self, forKey: .angle) ?? 0
        flipH = try c.decodeIfPresent(Bool.self, forKey: .flipH) ?? false
        flipV = try c.decodeIfPresent(Bool.self, forKey: .flipV) ?? false
        keystoneV = try c.decodeIfPresent(Double.self, forKey: .keystoneV) ?? 0
        keystoneH = try c.decodeIfPresent(Double.self, forKey: .keystoneH) ?? 0
    }
}

enum GeometryOps {
    static func apply(_ spec: CropSpec, to image: CIImage) -> CIImage {
        guard !spec.isIdentity else { return image }
        var img = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

        if spec.keystoneV != 0 || spec.keystoneH != 0 { img = keystone(img, v: spec.keystoneV, h: spec.keystoneH) }

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

    /// Straightens leaning lines: the image is rectified from a slightly inset quadrilateral, so nothing outside the picture is invented.
    static func keystone(_ img: CIImage, v: Double, h: Double) -> CIImage {
        let e = img.extent
        let dx = e.width * 0.12 * abs(v), dy = e.height * 0.12 * abs(h)
        // CI is y-up: top edge is maxY. v > 0 pulls the top edge in (stretching it out); v < 0 the bottom edge.
        var tl = CGPoint(x: e.minX, y: e.maxY), tr = CGPoint(x: e.maxX, y: e.maxY), bl = CGPoint(x: e.minX, y: e.minY), br = CGPoint(x: e.maxX, y: e.minY)
        if v > 0 { tl.x += dx; tr.x -= dx } else if v < 0 { bl.x += dx; br.x -= dx }
        if h > 0 { tl.y -= dy; bl.y += dy } else if h < 0 { tr.y -= dy; br.y += dy }
        let f = CIFilter(name: "CIPerspectiveCorrection", parameters: [kCIInputImageKey: img.clampedToExtent(), "inputTopLeft": CIVector(cgPoint: tl), "inputTopRight": CIVector(cgPoint: tr), "inputBottomLeft": CIVector(cgPoint: bl), "inputBottomRight": CIVector(cgPoint: br)])
        guard let out = f?.outputImage, out.extent.width.isFinite else { return img }
        // the corrected picture is the size of the quadrilateral's bounding box; scale back to the original frame
        let o = out.extent
        let t = CGAffineTransform(translationX: -o.minX, y: -o.minY).concatenating(CGAffineTransform(scaleX: e.width / o.width, y: e.height / o.height))
        return out.transformed(by: t).cropped(to: CGRect(origin: .zero, size: e.size))
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
        // Whole pixels, pulled 1px inside so antialiased rotated edges never show.
        let x0 = ceil(c.x - w / 2) + 1, y0 = ceil(c.y - h / 2) + 1
        let x1 = floor(c.x + w / 2) - 1, y1 = floor(c.y + h / 2) - 1
        guard x1 > x0, y1 > y0 else { return img }
        return rotated.cropped(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
    }

    /// Largest same-aspect rect that fits inside a w×h frame rotated by `radians`.
    static func insetSize(width w: CGFloat, height h: CGFloat, radians a: CGFloat) -> (CGFloat, CGFloat) {
        guard w > 0, h > 0 else { return (0, 0) }
        let s = abs(sin(a)), c = abs(cos(a))
        let scale = 1 / (c + s * max(w / h, h / w))
        return (w * scale, h * scale)
    }
}
