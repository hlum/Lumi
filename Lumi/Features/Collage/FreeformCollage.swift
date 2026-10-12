import CoreGraphics
import CoreImage
import Foundation

/// Scrapbook: photos placed anywhere with their own size, turn and stacking order.
struct FreeformCollage: Codable, Equatable {
    struct Item: Codable, Equatable {
        var photo: Int
        var center = CGPoint(x: 0.5, y: 0.5)     // canvas-normalized, y-down
        var width = 0.5                          // fraction of canvas width
        var rotation = 0.0                       // radians
    }
    var aspect = 1.0
    var items: [Item] = []

    mutating func add(photo: Int) {
        let n = Double(items.count)               // each new photo lands a little off the last
        items.append(Item(photo: photo, center: CGPoint(x: 0.4 + 0.05 * n.truncatingRemainder(dividingBy: 5), y: 0.4 + 0.05 * n.truncatingRemainder(dividingBy: 5))))
    }
    mutating func bringToFront(_ i: Int) { if items.indices.contains(i) { items.append(items.remove(at: i)) } }
    mutating func remove(_ i: Int) { if items.indices.contains(i) { items.remove(at: i) } }
    mutating func move(_ i: Int, to p: CGPoint) {
        if items.indices.contains(i) { items[i].center = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1)) }
    }
    mutating func scale(_ i: Int, by k: Double) { if items.indices.contains(i) { items[i].width = min(max(items[i].width * k, 0.1), 1.5) } }
    mutating func rotate(_ i: Int, by r: Double) { if items.indices.contains(i) { items[i].rotation += r } }

    /// Topmost item containing a canvas-normalized point (hit-test for dragging).
    func item(at p: CGPoint, photoAspects: [Double]) -> Int? {
        for i in items.indices.reversed() {
            let it = items[i]
            let a = photoAspects.indices.contains(it.photo) ? photoAspects[it.photo] : 1
            let hw = it.width / 2, hh = it.width / a / aspect / 2            // half sizes, canvas-normalized
            let dx = Double(p.x - it.center.x), dy = Double(p.y - it.center.y)
            let c = cos(-it.rotation), s = sin(-it.rotation)
            let lx = dx * c - dy * s, ly = dx * s + dy * c
            if abs(lx) <= hw && abs(ly) <= hh { return i }
        }
        return nil
    }
}

enum FreeformRenderer {
    static func render(_ f: FreeformCollage, photos: [CIImage], width: Int, background: RGBA = .white) -> CIImage {
        let w = CGFloat(max(width, 16)), h = (w / CGFloat(f.aspect)).rounded()
        let canvas = CGRect(x: 0, y: 0, width: w, height: h)
        var out = CIImage(color: CIColor(red: background.r, green: background.g, blue: background.b)).cropped(to: canvas)
        for it in f.items where photos.indices.contains(it.photo) {
            let p = photos[it.photo], e = p.extent
            let s = it.width * w / e.width
            let t = CGAffineTransform(translationX: -e.midX, y: -e.midY).concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(rotationAngle: -it.rotation))                        // y-up: turn the other way
                .concatenating(CGAffineTransform(translationX: it.center.x * w, y: (1 - it.center.y) * h))
            out = p.transformed(by: t).composited(over: out).cropped(to: canvas)
        }
        return out
    }
}
