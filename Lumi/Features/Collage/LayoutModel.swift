import CoreGraphics
import Foundation

struct CollageLayout: Codable, Equatable, Identifiable {
    enum Shape: String, Codable { case rect, heart, triangle, circle }
    struct Slot: Codable, Equatable { var rect: CGRect; var shape = Shape.rect }
    var id: String
    var name: String
    var aspect: Double          // canvas width / height
    var slots: [Slot]

    /// Equal grid with `gap` (fraction of the canvas width) between and around cells.
    static func grid(rows: Int, cols: Int, aspect: Double = 1, gap: Double = 0.02) -> CollageLayout {
        precondition(rows >= 1 && cols >= 1)
        let gx = gap, gy = gap * aspect
        let w = (1 - gx * Double(cols + 1)) / Double(cols), h = (1 - gy * Double(rows + 1)) / Double(rows)
        var slots: [Slot] = []
        for r in 0..<rows { for c in 0..<cols {
            slots.append(Slot(rect: CGRect(x: gx + Double(c) * (w + gx), y: gy + Double(r) * (h + gy), width: w, height: h)))
        } }
        return CollageLayout(id: "grid-\(rows)x\(cols)", name: "\(rows)×\(cols)", aspect: aspect, slots: slots)
    }

    /// Bundled layouts: every grid up to 4×4 in a few aspects, plus a 9-grid and shape layouts.
    static let builtin: [CollageLayout] = {
        var out: [CollageLayout] = []
        for aspect in [1.0, 3.0 / 4, 4.0 / 3, 9.0 / 16] {
            for rows in 1...4 { for cols in 1...4 where rows * cols >= 2 {
                var l = grid(rows: rows, cols: cols, aspect: aspect)
                l.id += "-\(Int(aspect * 100))"
                out.append(l)
            } }
        }
        var nine = grid(rows: 3, cols: 3, gap: 0.01); nine.id = "nine-grid"; nine.name = "9-grid"
        var heart = grid(rows: 1, cols: 1, gap: 0.08); heart.id = "heart"; heart.name = "Heart"; heart.slots[0].shape = .heart
        var tri = grid(rows: 1, cols: 1, gap: 0.08); tri.id = "triangle"; tri.name = "Triangle"; tri.slots[0].shape = .triangle
        return out + [nine, heart, tri]
    }()

    /// "AI collage": pick the layout with exactly `aspects.count` slots whose slot shape best matches the photos.
    static func autoPick(photoAspects aspects: [Double], from layouts: [CollageLayout] = builtin) -> CollageLayout? {
        let candidates = layouts.filter { $0.slots.count == aspects.count }
        let mean = aspects.reduce(0, +) / Double(max(aspects.count, 1))
        return candidates.min { a, b in cost(a, mean) < cost(b, mean) }
    }
    private static func cost(_ l: CollageLayout, _ photoAspect: Double) -> Double {
        let slotAspect = l.slots.map { Double($0.rect.width / $0.rect.height) * l.aspect }.reduce(0, +) / Double(l.slots.count)
        return abs(log(slotAspect / photoAspect))
    }
}

/// Which photo sits in which slot, with per-slot pan/zoom.
struct CollageState: Codable, Equatable {
    struct Fill: Codable, Equatable { var photo: Int; var zoom = 1.0; var pan = CGPoint.zero }   // pan in -1...1
    var layout: CollageLayout
    var fills: [Fill]
    var border = 0.0, cornerRadius = 0.0

    init(layout: CollageLayout, photoCount: Int) {
        self.layout = layout
        fills = (0..<layout.slots.count).map { Fill(photo: $0 % max(photoCount, 1)) }
    }

    mutating func swap(_ a: Int, _ b: Int) {
        guard fills.indices.contains(a), fills.indices.contains(b), a != b else { return }
        let pa = fills[a].photo; fills[a].photo = fills[b].photo; fills[b].photo = pa
    }
    mutating func setZoom(_ z: Double, slot: Int) { if fills.indices.contains(slot) { fills[slot].zoom = min(max(z, 1), 8) } }
    mutating func setPan(_ p: CGPoint, slot: Int) {
        if fills.indices.contains(slot) { fills[slot].pan = CGPoint(x: min(max(p.x, -1), 1), y: min(max(p.y, -1), 1)) }
    }
}

enum CollageMath {
    /// Source crop (in image pixels) that fills a slot: aspect-fill, then zoom and pan, never leaving the image.
    static func sourceCrop(image: CGSize, slotAspect: Double, zoom: Double, pan: CGPoint) -> CGRect {
        guard image.width > 0, image.height > 0, slotAspect > 0 else { return .zero }
        let imgAspect = Double(image.width / image.height)
        var w = Double(image.width), h = Double(image.height)
        if imgAspect > slotAspect { w = h * slotAspect } else { h = w / slotAspect }
        w /= max(zoom, 1); h /= max(zoom, 1)
        let slackX = Double(image.width) - w, slackY = Double(image.height) - h
        let x = slackX * (min(max(pan.x, -1), 1) + 1) / 2, y = slackY * (min(max(pan.y, -1), 1) + 1) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
