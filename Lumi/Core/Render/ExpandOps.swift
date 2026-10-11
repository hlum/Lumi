import CoreImage

/// Grows the canvas and asks the inpainter to fill the new border (outpainting).
struct ExpandConfig: Codable, Equatable {
    /// Added space per side as a fraction of the original width/height.
    var left = 0.0, right = 0.0, top = 0.0, bottom = 0.0
    var isIdentity: Bool { left == 0 && right == 0 && top == 0 && bottom == 0 }

    mutating func clamp() {
        func c(_ v: Double) -> Double { min(max(v, 0), 1) }
        left = c(left); right = c(right); top = c(top); bottom = c(bottom)
    }

    /// Padding that turns `size` into the target aspect (w/h) by adding space on the short axis, split evenly.
    static func toAspect(_ target: Double, from size: CGSize) -> ExpandConfig {
        guard target > 0, size.width > 0, size.height > 0 else { return ExpandConfig() }
        let have = Double(size.width / size.height)
        var c = ExpandConfig()
        if target > have {
            let add = (target / have - 1) / 2; c.left = add; c.right = add
        } else if target < have {
            let add = (have / target - 1) / 2; c.top = add; c.bottom = add
        }
        c.clamp()
        return c
    }

    func newSize(from size: CGSize) -> CGSize {
        CGSize(width: size.width * (1 + left + right), height: size.height * (1 + top + bottom))
    }
}

enum ExpandOps {
    /// Canvas for the expanded image (origin at zero) and the mask of the new area (white = to fill).
    static func plan(_ c: ExpandConfig, image: CIImage) -> (canvas: CGRect, mask: CIImage, placed: CIImage) {
        var cfg = c; cfg.clamp()
        let e = image.extent
        let l = e.width * cfg.left, r = e.width * cfg.right, t = e.height * cfg.top, b = e.height * cfg.bottom
        let canvas = CGRect(x: 0, y: 0, width: (e.width + l + r).rounded(), height: (e.height + t + b).rounded())
        // CI y is up: "bottom" padding sits at low y, "top" at high y.
        let placed = image.transformed(by: CGAffineTransform(translationX: -e.minX + l, y: -e.minY + b))
        let inner = CIImage(color: .black).cropped(to: placed.extent)
        let mask = inner.composited(over: CIImage(color: .white).cropped(to: canvas)).cropped(to: canvas)
        // overlap the seam a few pixels so the fill blends into real pixels
        let seam = Double(max(canvas.width, canvas.height)) * 0.004
        let grown = mask.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: seam]).cropped(to: canvas)
        return (canvas, grown, placed)
    }

    static func apply(_ c: ExpandConfig, to image: CIImage, inpainter: Inpainting) throws -> CIImage {
        guard !c.isIdentity else { return image }
        let p = plan(c, image: image)
        // first fill the border by stretching edge pixels, so the model starts from plausible color
        let base = p.placed.clampedToExtent().cropped(to: p.canvas)
        return try inpainter.inpaint(base, mask: p.mask).cropped(to: p.canvas)
    }
}
