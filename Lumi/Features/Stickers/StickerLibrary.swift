import CoreImage
import UIKit

/// Vector stickers drawn in code: nothing to license, and they stay sharp at any export size.
struct StickerInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let color: RGBA
    var keywords: [String] = []
}

enum StickerLibrary {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: 1) }
    private static let pink = rgb(1, 0.45, 0.6), yellow = rgb(1, 0.82, 0.2), blue = rgb(0.35, 0.65, 1), mint = rgb(0.4, 0.85, 0.7), red = rgb(0.95, 0.25, 0.3), white = rgb(1, 1, 1), purple = rgb(0.65, 0.5, 0.95), orange = rgb(1, 0.6, 0.2)

    static let all: [StickerInfo] = [
        StickerInfo(id: "heart", name: "Heart", category: "shapes", color: red, keywords: ["love", "ハート"]),
        StickerInfo(id: "star5", name: "Star", category: "shapes", color: yellow, keywords: ["favorite", "星"]),
        StickerInfo(id: "star4", name: "Twinkle", category: "sparkle", color: white, keywords: ["shine", "きらきら"]),
        StickerInfo(id: "star6", name: "Six star", category: "shapes", color: blue),
        StickerInfo(id: "star8", name: "Burst", category: "shapes", color: orange),
        StickerInfo(id: "sparkle", name: "Sparkle", category: "sparkle", color: white, keywords: ["glitter"]),
        StickerInfo(id: "circle", name: "Dot", category: "shapes", color: pink),
        StickerInfo(id: "ring", name: "Ring", category: "shapes", color: white),
        StickerInfo(id: "diamond", name: "Diamond", category: "shapes", color: blue),
        StickerInfo(id: "triangle", name: "Triangle", category: "shapes", color: mint),
        StickerInfo(id: "drop", name: "Drop", category: "nature", color: blue, keywords: ["water", "rain"]),
        StickerInfo(id: "cloud", name: "Cloud", category: "nature", color: white, keywords: ["sky", "雲"]),
        StickerInfo(id: "sun", name: "Sun", category: "nature", color: yellow, keywords: ["summer", "太陽"]),
        StickerInfo(id: "moon", name: "Moon", category: "nature", color: yellow, keywords: ["night", "月"]),
        StickerInfo(id: "flower5", name: "Flower", category: "nature", color: pink, keywords: ["blossom", "花"]),
        StickerInfo(id: "flower6", name: "Daisy", category: "nature", color: white),
        StickerInfo(id: "flower8", name: "Bloom", category: "nature", color: purple),
        StickerInfo(id: "leaf", name: "Leaf", category: "nature", color: mint),
        StickerInfo(id: "bolt", name: "Bolt", category: "symbols", color: yellow, keywords: ["lightning", "flash"]),
        StickerInfo(id: "arrow", name: "Arrow", category: "symbols", color: red),
        StickerInfo(id: "check", name: "Check", category: "symbols", color: mint),
        StickerInfo(id: "plus", name: "Plus", category: "symbols", color: blue),
        StickerInfo(id: "crown", name: "Crown", category: "symbols", color: yellow, keywords: ["king", "queen", "王冠"]),
        StickerInfo(id: "bubble", name: "Speech", category: "speech", color: white, keywords: ["chat", "吹き出し"]),
        StickerInfo(id: "bubble-round", name: "Round speech", category: "speech", color: pink),
        StickerInfo(id: "thought", name: "Thought", category: "speech", color: white),
        StickerInfo(id: "banner", name: "Banner", category: "speech", color: red, keywords: ["ribbon"]),
        StickerInfo(id: "tag", name: "Tag", category: "speech", color: orange),
        StickerInfo(id: "butterfly", name: "Butterfly", category: "nature", color: purple, keywords: ["蝶"]),
        StickerInfo(id: "sparkles", name: "Sparkles", category: "sparkle", color: yellow),
    ]

    static var categories: [String] { var s = Set<String>(); return all.map(\.category).filter { s.insert($0).inserted } }

    // MARK: shapes in the unit square (y down)

    private static func poly(_ n: Int, inner: Double, rotate: Double = -.pi / 2) -> UIBezierPath {
        let p = UIBezierPath()
        for i in 0..<(n * 2) {
            let a = rotate + Double(i) * .pi / Double(n), r = i % 2 == 0 ? 0.48 : 0.48 * inner
            let pt = CGPoint(x: 0.5 + r * cos(a), y: 0.5 + r * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.close(); return p
    }
    private static func flower(_ petals: Int) -> UIBezierPath {
        let p = UIBezierPath()
        for i in 0..<petals {
            let a = Double(i) * 2 * .pi / Double(petals), c = CGPoint(x: 0.5 + 0.27 * cos(a), y: 0.5 + 0.27 * sin(a))
            p.append(UIBezierPath(ovalIn: CGRect(x: c.x - 0.2, y: c.y - 0.2, width: 0.4, height: 0.4)))
        }
        p.append(UIBezierPath(ovalIn: CGRect(x: 0.32, y: 0.32, width: 0.36, height: 0.36)))
        return p
    }

    static func path(_ id: String) -> UIBezierPath? {
        switch id {
        case "star5": return poly(5, inner: 0.45)
        case "star4": return poly(4, inner: 0.3)
        case "star6": return poly(6, inner: 0.55)
        case "star8": return poly(8, inner: 0.65)
        case "sparkle":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.5, y: 0.02))
            p.addQuadCurve(to: CGPoint(x: 0.98, y: 0.5), controlPoint: CGPoint(x: 0.55, y: 0.45)); p.addQuadCurve(to: CGPoint(x: 0.5, y: 0.98), controlPoint: CGPoint(x: 0.55, y: 0.55))
            p.addQuadCurve(to: CGPoint(x: 0.02, y: 0.5), controlPoint: CGPoint(x: 0.45, y: 0.55)); p.addQuadCurve(to: CGPoint(x: 0.5, y: 0.02), controlPoint: CGPoint(x: 0.45, y: 0.45)); p.close(); return p
        case "heart":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.5, y: 0.9))
            p.addCurve(to: CGPoint(x: 0.08, y: 0.35), controlPoint1: CGPoint(x: 0.15, y: 0.7), controlPoint2: CGPoint(x: 0.02, y: 0.5))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.25), controlPoint1: CGPoint(x: 0.12, y: 0.1), controlPoint2: CGPoint(x: 0.4, y: 0.1))
            p.addCurve(to: CGPoint(x: 0.92, y: 0.35), controlPoint1: CGPoint(x: 0.6, y: 0.1), controlPoint2: CGPoint(x: 0.88, y: 0.1))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.9), controlPoint1: CGPoint(x: 0.98, y: 0.5), controlPoint2: CGPoint(x: 0.85, y: 0.7)); p.close(); return p
        case "circle": return UIBezierPath(ovalIn: CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.92))
        case "ring":
            let p = UIBezierPath(ovalIn: CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.92)); p.append(UIBezierPath(ovalIn: CGRect(x: 0.24, y: 0.24, width: 0.52, height: 0.52))); p.usesEvenOddFillRule = true; return p
        case "diamond": return diamond()
        case "triangle":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.5, y: 0.08)); p.addLine(to: CGPoint(x: 0.94, y: 0.88)); p.addLine(to: CGPoint(x: 0.06, y: 0.88)); p.close(); return p
        case "drop":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.5, y: 0.04))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.96), controlPoint1: CGPoint(x: 0.95, y: 0.5), controlPoint2: CGPoint(x: 0.85, y: 0.96))
            p.addCurve(to: CGPoint(x: 0.5, y: 0.04), controlPoint1: CGPoint(x: 0.15, y: 0.96), controlPoint2: CGPoint(x: 0.05, y: 0.5)); p.close(); return p
        case "cloud":
            let p = UIBezierPath()
            for r in [CGRect(x: 0.05, y: 0.4, width: 0.4, height: 0.4), CGRect(x: 0.25, y: 0.2, width: 0.45, height: 0.45), CGRect(x: 0.5, y: 0.35, width: 0.45, height: 0.45), CGRect(x: 0.2, y: 0.5, width: 0.6, height: 0.3)] { p.append(UIBezierPath(ovalIn: r)) }
            return p
        case "sun":
            let p = poly(12, inner: 0.7); p.append(UIBezierPath(ovalIn: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))); return p
        case "moon":
            return UIBezierPath(ovalIn: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))      // the bite is cut out in `image`
        case "flower5": return flower(5)
        case "flower6": return flower(6)
        case "flower8": return flower(8)
        case "leaf":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.1, y: 0.9))
            p.addCurve(to: CGPoint(x: 0.9, y: 0.1), controlPoint1: CGPoint(x: 0.1, y: 0.2), controlPoint2: CGPoint(x: 0.5, y: 0.05))
            p.addCurve(to: CGPoint(x: 0.1, y: 0.9), controlPoint1: CGPoint(x: 0.95, y: 0.6), controlPoint2: CGPoint(x: 0.6, y: 0.95)); p.close(); return p
        case "bolt":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.6, y: 0.02)); p.addLine(to: CGPoint(x: 0.2, y: 0.56)); p.addLine(to: CGPoint(x: 0.46, y: 0.56)); p.addLine(to: CGPoint(x: 0.36, y: 0.98))
            p.addLine(to: CGPoint(x: 0.82, y: 0.4)); p.addLine(to: CGPoint(x: 0.54, y: 0.4)); p.close(); return p
        case "arrow":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.04, y: 0.38)); p.addLine(to: CGPoint(x: 0.55, y: 0.38)); p.addLine(to: CGPoint(x: 0.55, y: 0.12)); p.addLine(to: CGPoint(x: 0.96, y: 0.5))
            p.addLine(to: CGPoint(x: 0.55, y: 0.88)); p.addLine(to: CGPoint(x: 0.55, y: 0.62)); p.addLine(to: CGPoint(x: 0.04, y: 0.62)); p.close(); return p
        case "check":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.08, y: 0.55)); p.addLine(to: CGPoint(x: 0.22, y: 0.4)); p.addLine(to: CGPoint(x: 0.42, y: 0.6)); p.addLine(to: CGPoint(x: 0.78, y: 0.2))
            p.addLine(to: CGPoint(x: 0.92, y: 0.35)); p.addLine(to: CGPoint(x: 0.42, y: 0.88)); p.close(); return p
        case "plus":
            let p = UIBezierPath(rect: CGRect(x: 0.38, y: 0.06, width: 0.24, height: 0.88)); p.append(UIBezierPath(rect: CGRect(x: 0.06, y: 0.38, width: 0.88, height: 0.24))); return p
        case "crown":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.06, y: 0.82)); p.addLine(to: CGPoint(x: 0.1, y: 0.3)); p.addLine(to: CGPoint(x: 0.32, y: 0.55)); p.addLine(to: CGPoint(x: 0.5, y: 0.2))
            p.addLine(to: CGPoint(x: 0.68, y: 0.55)); p.addLine(to: CGPoint(x: 0.9, y: 0.3)); p.addLine(to: CGPoint(x: 0.94, y: 0.82)); p.close(); return p
        case "bubble":
            let p = UIBezierPath(roundedRect: CGRect(x: 0.04, y: 0.1, width: 0.92, height: 0.62), cornerRadius: 0.12)
            let t = UIBezierPath(); t.move(to: CGPoint(x: 0.2, y: 0.7)); t.addLine(to: CGPoint(x: 0.16, y: 0.94)); t.addLine(to: CGPoint(x: 0.42, y: 0.7)); t.close(); p.append(t); return p
        case "bubble-round":
            let p = UIBezierPath(ovalIn: CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.78))
            let t = UIBezierPath(); t.move(to: CGPoint(x: 0.3, y: 0.76)); t.addLine(to: CGPoint(x: 0.22, y: 0.97)); t.addLine(to: CGPoint(x: 0.5, y: 0.8)); t.close(); p.append(t); return p
        case "thought":
            let p = UIBezierPath(ovalIn: CGRect(x: 0.04, y: 0.04, width: 0.92, height: 0.66))
            p.append(UIBezierPath(ovalIn: CGRect(x: 0.2, y: 0.74, width: 0.14, height: 0.14))); p.append(UIBezierPath(ovalIn: CGRect(x: 0.08, y: 0.9, width: 0.08, height: 0.08))); return p
        case "banner":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.02, y: 0.25)); p.addLine(to: CGPoint(x: 0.98, y: 0.25)); p.addLine(to: CGPoint(x: 0.88, y: 0.5)); p.addLine(to: CGPoint(x: 0.98, y: 0.75)); p.addLine(to: CGPoint(x: 0.02, y: 0.75)); p.addLine(to: CGPoint(x: 0.12, y: 0.5)); p.close(); return p
        case "tag":
            let p = UIBezierPath(); p.move(to: CGPoint(x: 0.06, y: 0.5)); p.addLine(to: CGPoint(x: 0.3, y: 0.15)); p.addLine(to: CGPoint(x: 0.94, y: 0.15)); p.addLine(to: CGPoint(x: 0.94, y: 0.85)); p.addLine(to: CGPoint(x: 0.3, y: 0.85)); p.close()
            p.append(UIBezierPath(ovalIn: CGRect(x: 0.24, y: 0.44, width: 0.12, height: 0.12))); p.usesEvenOddFillRule = true; return p
        case "butterfly":
            let p = UIBezierPath()
            for r in [CGRect(x: 0.04, y: 0.1, width: 0.46, height: 0.46), CGRect(x: 0.5, y: 0.1, width: 0.46, height: 0.46), CGRect(x: 0.12, y: 0.5, width: 0.38, height: 0.38), CGRect(x: 0.5, y: 0.5, width: 0.38, height: 0.38)] { p.append(UIBezierPath(ovalIn: r)) }
            p.append(UIBezierPath(roundedRect: CGRect(x: 0.46, y: 0.2, width: 0.08, height: 0.64), cornerRadius: 0.04)); return p
        case "sparkles":
            let p = UIBezierPath()
            for (c, s) in [(CGPoint(x: 0.35, y: 0.6), 0.55), (CGPoint(x: 0.75, y: 0.25), 0.3), (CGPoint(x: 0.78, y: 0.78), 0.22)] {
                let q = path("sparkle")!; q.apply(CGAffineTransform(translationX: -0.5, y: -0.5).concatenating(CGAffineTransform(scaleX: s, y: s)).concatenating(CGAffineTransform(translationX: c.x, y: c.y))); p.append(q)
            }
            return p
        default: return nil
        }
    }

    private static func diamond() -> UIBezierPath {
        let p = UIBezierPath(); p.move(to: CGPoint(x: 0.5, y: 0.04)); p.addLine(to: CGPoint(x: 0.92, y: 0.5)); p.addLine(to: CGPoint(x: 0.5, y: 0.96)); p.addLine(to: CGPoint(x: 0.08, y: 0.5)); p.close(); return p
    }

    /// The sticker as a transparent square image. `color` overrides the default tint.
    static func image(_ id: String, side: Int = 512, color: RGBA? = nil) -> CIImage? {
        if CustomStickerStore.isCustom(id) { return CustomStickerStore.shared.image(id) }       // user-made stickers are ready-made pictures
        guard let info = all.first(where: { $0.id == id }), let p = path(id) else { return nil }
        let c = color ?? info.color
        let s = CGFloat(side)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: fmt).image { _ in
            let q = p.copy() as! UIBezierPath
            q.apply(CGAffineTransform(scaleX: s, y: s))
            UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a).setFill()
            q.fill(with: .normal, alpha: 1)
            if id == "moon" {       // crescent = circle minus a shifted circle
                let bite = UIBezierPath(ovalIn: CGRect(x: 0.35, y: 0.02, width: 0.75, height: 0.75)); bite.apply(CGAffineTransform(scaleX: s, y: s))
                bite.fill(with: .clear, alpha: 1)
            }
        }
        return CIImage(image: img)
    }

    static func search(_ query: String) -> [StickerInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.lowercased().contains(q) || $0.category.contains(q) || $0.keywords.contains { $0.lowercased().contains(q) } }
    }
}
