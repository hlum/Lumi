import CoreImage

/// Joins screenshots or photos into one long picture. For screenshots it finds where one repeats the next and cuts the repeat.
enum Stitcher {
    enum Direction { case vertical, horizontal }
    static let analysisWidth = 180

    /// Rows (in each picture's own pixels) of repeat between consecutive pictures, 0 where none is found.
    static func overlaps(_ images: [CIImage], direction: Direction) -> [Int] {
        guard images.count > 1 else { return [] }
        let grays = images.map { gray($0, direction: direction) }
        return (0..<(images.count - 1)).map { i in
            guard let a = grays[i], let b = grays[i + 1], let rows = OverlapFinder.verticalOverlap(top: a.image, bottom: b.image) else { return 0 }
            return Int((Double(rows) / a.scale).rounded())
        }
    }

    /// Row-major gray bitmap of the picture; for a horizontal join it is rotated so the same row logic applies. `scale` = analysis px per picture px along the join.
    private static func gray(_ image: CIImage, direction: Direction) -> (image: GrayImage, scale: Double)? {
        var img = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if direction == .horizontal { img = img.transformed(by: CGAffineTransform(rotationAngle: -.pi / 2)); img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY)) }
        let e = img.extent
        guard e.width > 0, e.height > 0 else { return nil }
        let k = Double(analysisWidth) / Double(e.width)
        let w = analysisWidth, h = max(Int((Double(e.height) * k).rounded()), 1)
        let small = img.transformed(by: CGAffineTransform(scaleX: CGFloat(w) / e.width, y: CGFloat(h) / e.height)).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        var px = [UInt8](repeating: 0, count: w * h)
        CIContext().render(small, toBitmap: &px, rowBytes: w, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .R8, colorSpace: nil)
        return (GrayImage(width: w, height: h, pixels: px), k)
    }

    /// The joined picture. Pictures are scaled to a common width (or height) first; `cutOverlap` removes repeated rows.
    static func stitch(_ images: [CIImage], direction: Direction, cutOverlap: Bool) -> CIImage? {
        guard !images.isEmpty else { return nil }
        let norm = images.map { $0.transformed(by: CGAffineTransform(translationX: -$0.extent.minX, y: -$0.extent.minY)) }
        // scale all to the first picture's cross size
        let cross = direction == .vertical ? norm[0].extent.width : norm[0].extent.height
        let scaled: [CIImage] = norm.map { i in
            let c = direction == .vertical ? i.extent.width : i.extent.height
            return c == cross ? i : i.transformed(by: CGAffineTransform(scaleX: cross / c, y: cross / c))
        }
        let cuts = cutOverlap ? overlaps(scaled, direction: direction) : Array(repeating: 0, count: max(scaled.count - 1, 0))
        var out = CIImage(color: .clear).cropped(to: .zero)
        var offset: CGFloat = 0
        var total: CGFloat = 0
        for (i, img) in scaled.enumerated() {
            let along = direction == .vertical ? img.extent.height : img.extent.width
            total += along - (i == 0 ? 0 : CGFloat(cuts[i - 1]))
        }
        let canvas = direction == .vertical ? CGRect(x: 0, y: 0, width: cross, height: total) : CGRect(x: 0, y: 0, width: total, height: cross)
        out = CIImage(color: .clear).cropped(to: canvas)
        for (i, img) in scaled.enumerated() {
            let cut = i == 0 ? 0 : CGFloat(cuts[i - 1])
            let along = direction == .vertical ? img.extent.height : img.extent.width
            // vertical: the first picture is at the top (CI y grows upward), so place pieces from the top down
            let part: CIImage
            let placed: CIImage
            if direction == .vertical {
                part = img.cropped(to: CGRect(x: 0, y: 0, width: img.extent.width, height: along - cut))          // drop the repeated rows: they are at the TOP of this picture, which is its maxY side
                placed = part.transformed(by: CGAffineTransform(translationX: 0, y: total - offset - part.extent.height))
            } else {
                part = img.cropped(to: CGRect(x: cut, y: 0, width: along - cut, height: img.extent.height))
                placed = part.transformed(by: CGAffineTransform(translationX: offset - cut, y: 0))
            }
            out = placed.composited(over: out)
            offset += direction == .vertical ? part.extent.height : part.extent.width
        }
        return out.cropped(to: canvas)
    }
}
