import CoreImage
import Vision

/// One person found in a photo.
struct PersonInstance: Equatable {
    var mask: CIImage          // white = this person, same extent as the photo
    var box: CGRect            // normalized, origin bottom-left
    var area: Double { Double(box.width * box.height) }
    static func == (a: PersonInstance, b: PersonInstance) -> Bool { a.box == b.box }
}

protocol PeopleFinding { func people(in image: CIImage) throws -> [PersonInstance] }

struct VisionPeopleFinder: PeopleFinding {
    func people(in image: CIImage) throws -> [PersonInstance] {
        let req = VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([req])
        guard let obs = req.results?.first else { return [] }
        return try obs.allInstances.compactMap { idx in
            let buf = try obs.generateScaledMaskForImage(forInstances: IndexSet(integer: idx), from: handler)
            let mask = CIImage(cvPixelBuffer: buf).cropped(to: image.extent)
            guard let b = MaskBounds.normalizedBounds(of: mask) else { return nil }
            return PersonInstance(mask: mask, box: b)
        }
    }
}

/// Things in the photo that are not people: found as foreground instances that no person covers.
protocol ObjectFinding { func objects(in image: CIImage, people: [PersonInstance]) throws -> [PersonInstance] }

struct VisionObjectFinder: ObjectFinding {
    func objects(in image: CIImage, people: [PersonInstance]) throws -> [PersonInstance] {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([req])
        guard let obs = req.results?.first else { return [] }
        let found: [PersonInstance] = try obs.allInstances.compactMap { idx in
            let buf = try obs.generateScaledMaskForImage(forInstances: IndexSet(integer: idx), from: handler)
            let mask = CIImage(cvPixelBuffer: buf).cropped(to: image.extent)
            guard let b = MaskBounds.normalizedBounds(of: mask) else { return nil }
            return PersonInstance(mask: mask, box: b)
        }
        return AutoRemove.objects(from: found, excluding: people)
    }
}

enum MaskBounds {
    /// Bounding box of the white area, normalized with a bottom-left origin; nil if empty.
    static func normalizedBounds(of mask: CIImage) -> CGRect? {
        let e = mask.extent
        let n = 64
        let small = mask.transformed(by: CGAffineTransform(scaleX: CGFloat(n) / e.width, y: CGFloat(n) / e.height).translatedBy(x: -e.minX, y: -e.minY))
        var px = [UInt8](repeating: 0, count: n * n * 4)
        CIContext().render(small, toBitmap: &px, rowBytes: n * 4, bounds: CGRect(x: 0, y: 0, width: n, height: n), format: .RGBA8, colorSpace: nil)
        var minX = n, minY = n, maxX = -1, maxY = -1
        for y in 0..<n { for x in 0..<n where px[(y * n + x) * 4] > 100 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX >= 0 else { return nil }
        let s = 1.0 / CGFloat(n)
        return CGRect(x: CGFloat(minX) * s, y: CGFloat(n - 1 - maxY) * s, width: CGFloat(maxX - minX + 1) * s, height: CGFloat(maxY - minY + 1) * s)
    }
}

enum AutoRemove {
    /// The main subject is the person who is biggest and closest to the center; everyone else is a passer-by.
    static func mainSubject(_ people: [PersonInstance]) -> PersonInstance? {
        people.max { score($0) < score($1) }
    }
    private static func score(_ p: PersonInstance) -> Double {
        let dx = Double(p.box.midX) - 0.5, dy = Double(p.box.midY) - 0.5
        return p.area * (1 - min((dx * dx + dy * dy).squareRoot(), 0.7))
    }

    /// Instances that are not (mostly) a person. Overlap is measured on the boxes.
    static func objects(from instances: [PersonInstance], excluding people: [PersonInstance], overlap: Double = 0.5) -> [PersonInstance] {
        instances.filter { inst in
            !people.contains { p in
                let i = inst.box.intersection(p.box)
                guard !i.isNull, inst.area > 0 else { return false }
                return Double(i.width * i.height) / inst.area > overlap
            }
        }
    }

    static func passersBy(_ people: [PersonInstance]) -> [PersonInstance] {
        guard let main = mainSubject(people) else { return [] }
        return people.filter { $0 != main }
    }

    /// Union of the people's masks, slightly grown so shadows and edges go too.
    static func combinedMask(_ people: [PersonInstance], extent: CGRect, grow: Double = 6) -> CIImage? {
        guard !people.isEmpty else { return nil }
        let base = CIImage(color: .black).cropped(to: extent)
        let union = people.reduce(base) { $1.mask.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]).cropped(to: extent) }
        return union.clampedToExtent().applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: grow]).cropped(to: extent)
    }

    /// Mask for text lines, each box a little larger so the glyph edges are covered.
    static func textMask(_ boxes: [CGRect], extent: CGRect) -> CIImage? {
        guard !boxes.isEmpty else { return nil }
        return MosaicOps.mask(rects: boxes.map { $0.insetBy(dx: -0.01, dy: -0.006).intersection(CGRect(x: 0, y: 0, width: 1, height: 1)) }, extent: extent)
    }
}
