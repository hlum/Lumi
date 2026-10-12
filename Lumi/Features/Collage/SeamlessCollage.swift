import CoreGraphics
import Foundation

extension CollageLayout {
    /// Two or three photos side by side or stacked, with the split at `ratio` (first photo's share).
    static func split(vertical: Bool, ratio: Double = 0.5, aspect: Double = 1, gap: Double = 0) -> CollageLayout {
        let r = min(max(ratio, 0.2), 0.8)
        let a = vertical ? CGRect(x: 0, y: 0, width: r - gap / 2, height: 1) : CGRect(x: 0, y: 0, width: 1, height: r - gap / 2)
        let b = vertical ? CGRect(x: r + gap / 2, y: 0, width: 1 - r - gap / 2, height: 1) : CGRect(x: 0, y: r + gap / 2, width: 1, height: 1 - r - gap / 2)
        return CollageLayout(id: "split-\(vertical ? "v" : "h")-\(Int(r * 100))", name: vertical ? "Split left/right" : "Split top/bottom", aspect: aspect, slots: [.init(rect: a), .init(rect: b)])
    }

    /// Same slots with no gaps at all: photos meet edge to edge. Grids only.
    var seamless: CollageLayout {
        guard let first = slots.first, first.shape == .rect else { return self }
        let xs = Set(slots.map { $0.rect.minX.rounded(toPlaces: 4) }).sorted(), ys = Set(slots.map { $0.rect.minY.rounded(toPlaces: 4) }).sorted()
        guard xs.count * ys.count == slots.count else { return self }          // not a regular grid
        var l = self; l.id += "-seamless"
        l.slots = slots.map { s in
            let c = xs.firstIndex(of: s.rect.minX.rounded(toPlaces: 4))!, r = ys.firstIndex(of: s.rect.minY.rounded(toPlaces: 4))!
            return .init(rect: CGRect(x: Double(c) / Double(xs.count), y: Double(r) / Double(ys.count), width: 1 / Double(xs.count), height: 1 / Double(ys.count)))
        }
        return l
    }
}

private extension CGFloat {
    func rounded(toPlaces n: Int) -> CGFloat { let m = pow(10, CGFloat(n)); return (self * m).rounded() / m }
}

/// A saved collage look: layout plus filter and stickers on top.
struct CollageRecipe: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var layoutID: String
    var filterID: String?
    var stickers: [String]            // sticker ids, placed along the bottom edge
    var border = 0.0
    var cornerRadius = 0.0

    static let builtin: [CollageRecipe] = [
        .init(id: "polaroid-pair", name: "Polaroid pair", layoutID: "grid-1x2-100", filterID: nil, stickers: ["heart"], border: 0.03, cornerRadius: 0.04),
        .init(id: "seamless-quad", name: "Seamless four", layoutID: "grid-2x2-100", filterID: nil, stickers: [], border: 0, cornerRadius: 0),
        .init(id: "nine-pop", name: "Nine pop", layoutID: "nine-grid", filterID: nil, stickers: ["star"], border: 0.004, cornerRadius: 0.02),
    ]

    func state(photoCount: Int, layouts: [CollageLayout] = CollageLayout.builtin) -> CollageState? {
        guard var l = layouts.first(where: { $0.id == layoutID }) else { return nil }
        if border == 0 && layoutID.hasPrefix("grid") { l = l.seamless }
        var s = CollageState(layout: l, photoCount: photoCount)
        s.border = border; s.cornerRadius = cornerRadius
        return s
    }
}
