import CoreGraphics
import CoreImage

/// Skin mask for one face: the face contour filled, with eyes, brows and lips cut out, then feathered.
enum SkinMask {
    static func make(face: FaceInfo, size: CGSize, feather: CGFloat = 0.02) -> CIImage? {
        let contour = FaceReshape.points(face, "faceContour")
        guard contour.count >= 3, size.width > 0, size.height > 0, size.width * size.height < 100_000_000 else { return nil }
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        // CGContext y is up; our points are y-down normalized, so flip y when mapping.
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height) }
        func fill(_ pts: [CGPoint], gray: CGFloat) {
            guard pts.count >= 3 else { return }
            ctx.setFillColor(gray: gray, alpha: 1)
            ctx.addLines(between: pts.map(px)); ctx.closePath(); ctx.fillPath()
        }
        // Vision's contour runs ear-to-ear along the jaw; close it over the forehead using the face box top.
        let top = 1 - (face.box.maxY)
        let closed = contour + [CGPoint(x: contour.last!.x, y: top), CGPoint(x: contour.first!.x, y: top)]
        fill(closed, gray: 1)
        for region in ["leftEye", "rightEye", "leftEyebrow", "rightEyebrow", "outerLips"] { fill(grow(FaceReshape.points(face, region)), gray: 0) }
        guard let cg = ctx.makeImage() else { return nil }
        let img = CIImage(cgImage: cg)
        guard feather > 0 else { return img }
        let r = Double(min(size.width, size.height) * feather)
        return img.clampedToExtent().applyingGaussianBlur(sigma: r).cropped(to: img.extent)
    }

    /// Expands a polygon about its center by 25% so cut-outs cover lashes and lip edges.
    private static func grow(_ pts: [CGPoint]) -> [CGPoint] {
        guard let c = FaceReshape.center(pts) else { return pts }
        return pts.map { CGPoint(x: c.x + ($0.x - c.x) * 1.25, y: c.y + ($0.y - c.y) * 1.25) }
    }
}
