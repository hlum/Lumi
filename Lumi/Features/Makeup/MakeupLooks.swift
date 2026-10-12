import CoreImage
import Foundation

struct MakeupLook: Identifiable, Equatable {
    let id: String
    let name: String          // localized through Localizable.xcstrings (key = name)
    let makeup: MakeupParams
    let eyes: EyeMakeup
}

/// Complete looks, drawn in code. Colors are plain numbers, so there is nothing to license.
enum MakeupLooks {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: 1) }

    private static func look(_ id: String, _ name: String, lip: RGBA, lipAmount: Double, finish: MakeupParams.Finish = .satin, ombre: Double = 0,
                             blush: RGBA, blushAmount: Double, style: MakeupParams.BlushStyle = .round, contour: Double = 0, highlight: Double = 0, foundation: Double = 0,
                             shadow: RGBA = rgb(0.6, 0.4, 0.5), shadowAmount: Double = 0, liner: Double = 0, lashes: Double = 0, brow: Double = 0) -> MakeupLook {
        var m = MakeupParams()
        m.lipColor = lip; m.lipOpacity = lipAmount; m.lipFinish = finish; m.ombre = ombre
        m.blushColor = blush; m.blushOpacity = blushAmount; m.blushStyle = style
        m.contour = contour; m.highlight = highlight; m.foundation = foundation
        var e = EyeMakeup()
        e.setBoth { $0.shadowColor = shadow; $0.shadow = shadowAmount; $0.liner = liner; $0.lashes = lashes }
        e.browOpacity = brow
        return MakeupLook(id: id, name: name, makeup: m, eyes: e)
    }

    static let all: [MakeupLook] = [
        look("nude", "Nude", lip: rgb(0.78, 0.5, 0.45), lipAmount: 0.4, finish: .matte, blush: rgb(0.9, 0.6, 0.55), blushAmount: 0.15, foundation: 0.3, shadow: rgb(0.75, 0.6, 0.55), shadowAmount: 0.2, lashes: 0.2),
        look("rose", "Rose", lip: rgb(0.85, 0.35, 0.45), lipAmount: 0.55, blush: rgb(0.95, 0.5, 0.55), blushAmount: 0.3, highlight: 0.2, shadow: rgb(0.85, 0.55, 0.6), shadowAmount: 0.3, lashes: 0.3),
        look("peach", "Peach", lip: rgb(0.95, 0.5, 0.4), lipAmount: 0.5, blush: rgb(1, 0.6, 0.45), blushAmount: 0.35, style: .wide, highlight: 0.25, shadow: rgb(0.95, 0.7, 0.55), shadowAmount: 0.3, liner: 0.2),
        look("coral", "Coral", lip: rgb(1, 0.4, 0.35), lipAmount: 0.6, finish: .gloss, blush: rgb(1, 0.55, 0.45), blushAmount: 0.3, shadow: rgb(0.95, 0.6, 0.5), shadowAmount: 0.25, lashes: 0.3),
        look("berry", "Berry", lip: rgb(0.6, 0.12, 0.3), lipAmount: 0.7, finish: .matte, blush: rgb(0.75, 0.3, 0.45), blushAmount: 0.3, contour: 0.2, shadow: rgb(0.45, 0.2, 0.35), shadowAmount: 0.35, liner: 0.4, lashes: 0.4, brow: 0.3),
        look("red-classic", "Classic red", lip: rgb(0.8, 0.05, 0.1), lipAmount: 0.85, finish: .satin, blush: rgb(0.9, 0.45, 0.45), blushAmount: 0.15, foundation: 0.4, shadow: rgb(0.7, 0.55, 0.5), shadowAmount: 0.15, liner: 0.6, lashes: 0.5, brow: 0.3),
        look("mauve", "Mauve", lip: rgb(0.65, 0.4, 0.5), lipAmount: 0.55, finish: .matte, blush: rgb(0.8, 0.5, 0.6), blushAmount: 0.25, shadow: rgb(0.55, 0.4, 0.55), shadowAmount: 0.3, lashes: 0.3),
        look("plum", "Plum", lip: rgb(0.45, 0.1, 0.3), lipAmount: 0.7, finish: .matte, blush: rgb(0.65, 0.3, 0.5), blushAmount: 0.25, contour: 0.25, shadow: rgb(0.35, 0.15, 0.4), shadowAmount: 0.4, liner: 0.5, lashes: 0.5),
        look("sunset", "Sunset", lip: rgb(0.95, 0.4, 0.3), lipAmount: 0.5, ombre: 0.4, blush: rgb(1, 0.5, 0.35), blushAmount: 0.35, style: .wide, highlight: 0.3, shadow: rgb(0.95, 0.55, 0.3), shadowAmount: 0.4, liner: 0.3),
        look("cherry", "Cherry", lip: rgb(0.75, 0.1, 0.2), lipAmount: 0.7, ombre: 0.5, blush: rgb(0.95, 0.4, 0.45), blushAmount: 0.3, shadow: rgb(0.8, 0.45, 0.5), shadowAmount: 0.2, lashes: 0.4),
        look("sakura", "Sakura", lip: rgb(0.95, 0.6, 0.65), lipAmount: 0.45, finish: .gloss, blush: rgb(1, 0.7, 0.75), blushAmount: 0.35, style: .oval, highlight: 0.3, shadow: rgb(1, 0.75, 0.8), shadowAmount: 0.3, lashes: 0.3),
        look("douyin", "Douyin", lip: rgb(0.9, 0.3, 0.4), lipAmount: 0.55, ombre: 0.45, blush: rgb(1, 0.55, 0.6), blushAmount: 0.4, style: .wide, highlight: 0.3, foundation: 0.35, shadow: rgb(0.85, 0.5, 0.55), shadowAmount: 0.3, liner: 0.4, lashes: 0.5, brow: 0.3),
        look("ulzzang", "Ulzzang", lip: rgb(0.95, 0.5, 0.5), lipAmount: 0.5, ombre: 0.5, blush: rgb(1, 0.65, 0.65), blushAmount: 0.3, highlight: 0.35, foundation: 0.3, shadow: rgb(0.9, 0.7, 0.65), shadowAmount: 0.25, lashes: 0.3),
        look("bronze", "Bronze", lip: rgb(0.7, 0.4, 0.3), lipAmount: 0.5, finish: .matte, blush: rgb(0.85, 0.5, 0.35), blushAmount: 0.3, style: .wide, contour: 0.45, highlight: 0.3, shadow: rgb(0.65, 0.45, 0.3), shadowAmount: 0.4, liner: 0.4, lashes: 0.4),
        look("smoky", "Smoky", lip: rgb(0.7, 0.45, 0.45), lipAmount: 0.4, finish: .matte, blush: rgb(0.8, 0.5, 0.5), blushAmount: 0.15, contour: 0.3, shadow: rgb(0.2, 0.18, 0.2), shadowAmount: 0.65, liner: 0.7, lashes: 0.7, brow: 0.4),
        look("natural-glow", "Natural glow", lip: rgb(0.85, 0.55, 0.5), lipAmount: 0.3, finish: .gloss, blush: rgb(0.95, 0.6, 0.55), blushAmount: 0.2, highlight: 0.45, foundation: 0.25, lashes: 0.15),
        look("office", "Office", lip: rgb(0.75, 0.4, 0.45), lipAmount: 0.45, finish: .matte, blush: rgb(0.85, 0.5, 0.5), blushAmount: 0.15, contour: 0.15, foundation: 0.4, shadow: rgb(0.7, 0.55, 0.5), shadowAmount: 0.2, liner: 0.3, lashes: 0.3, brow: 0.25),
        look("party", "Party", lip: rgb(0.85, 0.15, 0.35), lipAmount: 0.7, finish: .gloss, blush: rgb(0.95, 0.45, 0.55), blushAmount: 0.3, contour: 0.3, highlight: 0.5, shadow: rgb(0.55, 0.3, 0.7), shadowAmount: 0.5, liner: 0.6, lashes: 0.6, brow: 0.3),
        look("autumn", "Autumn", lip: rgb(0.65, 0.25, 0.2), lipAmount: 0.6, finish: .matte, blush: rgb(0.85, 0.45, 0.3), blushAmount: 0.3, style: .wide, contour: 0.25, shadow: rgb(0.6, 0.35, 0.2), shadowAmount: 0.4, liner: 0.35, lashes: 0.35),
        look("winter-berry", "Winter berry", lip: rgb(0.55, 0.1, 0.25), lipAmount: 0.65, finish: .satin, blush: rgb(0.8, 0.35, 0.45), blushAmount: 0.2, highlight: 0.2, foundation: 0.3, shadow: rgb(0.5, 0.45, 0.6), shadowAmount: 0.3, liner: 0.5, lashes: 0.45, brow: 0.3),
        look("fresh-face", "Fresh face", lip: rgb(0.9, 0.55, 0.55), lipAmount: 0.3, blush: rgb(1, 0.65, 0.6), blushAmount: 0.2, highlight: 0.2, foundation: 0.35, lashes: 0.1),
    ]

    static func look(_ id: String) -> MakeupLook? { all.first { $0.id == id } }

    /// A look scaled between "none" (0) and as designed (1).
    static func scaled(_ l: MakeupLook, strength: Double) -> (makeup: MakeupParams, eyes: EyeMakeup) {
        let s = min(max(strength, 0), 1)
        var m = l.makeup
        m.lipOpacity *= s; m.blushOpacity *= s; m.contour *= s; m.highlight *= s; m.foundation *= s; m.ombre *= s
        var e = l.eyes
        e.setBoth { $0.shadow *= s; $0.liner *= s; $0.lashes *= s }
        e.browOpacity *= s
        return (m, e)
    }
}

/// "Recreate from a reference photo": reads lip, blush and eyelid colors off a reference face.
enum RecreateLook {
    private static func average(_ image: CIImage, mask: CIImage) -> RGBA? {
        let e = image.extent
        var m = [UInt8](repeating: 0, count: Int(e.width) * Int(e.height))
        let ctx = CIContext()
        ctx.render(mask, toBitmap: &m, rowBytes: Int(e.width), bounds: e, format: .L8, colorSpace: nil)
        var px = [UInt8](repeating: 0, count: Int(e.width) * Int(e.height) * 4)
        ctx.render(image, toBitmap: &px, rowBytes: Int(e.width) * 4, bounds: e, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        // weighted by the mask, so soft masks (a shadow fading toward the brow) count their strong part most
        for i in 0..<m.count where m[i] > 32 { let w = Double(m[i]) / 255; r += w * Double(px[i * 4]); g += w * Double(px[i * 4 + 1]); b += w * Double(px[i * 4 + 2]); n += w }
        guard n > 3 else { return nil }
        return RGBA(r: r / n / 255, g: g / n / 255, b: b / n / 255, a: 1)
    }

    struct Colors: Equatable { var lip: RGBA?; var blush: RGBA?; var shadow: RGBA? }

    static func sample(_ image: CIImage, face: FaceInfo) -> Colors {
        let size = image.extent.size
        let lip = MakeupRenderer.lipMask(face, size: size).flatMap { average(image, mask: $0) }
        let blush = MakeupRenderer.spotsMask(MakeupRenderer.blushSpots(face, style: .round).map { MakeupRenderer.Spot(center: $0.center, radius: $0.radius * 0.5, squash: 1) }, size: size).flatMap { average(image, mask: $0) }
        let lids = ["leftEye", "rightEye"].compactMap { EyeMakeupRenderer.shadowMask(FaceReshape.points(face, $0), size: size) }
        let shadow = lids.first.flatMap { first in
            average(image, mask: lids.dropFirst().reduce(first) { $1.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]).cropped(to: first.extent) })
        }
        return Colors(lip: lip, blush: blush, shadow: shadow)
    }

    /// Makeup built from the sampled colors, at a moderate strength.
    static func look(from c: Colors) -> (makeup: MakeupParams, eyes: EyeMakeup) {
        var m = MakeupParams(), e = EyeMakeup()
        if let l = c.lip { m.lipColor = l; m.lipOpacity = 0.55 }
        if let b = c.blush { m.blushColor = b; m.blushOpacity = 0.3 }
        if let s = c.shadow { e.setBoth { $0.shadowColor = s; $0.shadow = 0.35 } }
        return (m, e)
    }
}
