import Foundation

/// One-tap looks combining skin, face reshape and makeup. Values are conservative on purpose.
struct BeautyLook: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var skin: SkinParams
    var face: FaceReshapeParams
    var makeup: MakeupParams
    var group = "Daily"

    init(id: String, name: String, skin: SkinParams, face: FaceReshapeParams, makeup: MakeupParams, group: String = "Daily") {
        self.id = id; self.name = name; self.skin = skin; self.face = face; self.makeup = makeup; self.group = group
    }
}

enum AutoBeauty {
    static let groups = ["For you", "Daily", "Glam", "Men"]

    private static func lips(_ opacity: Double, blush: Double = 0, finish: MakeupParams.Finish = .satin) -> MakeupParams {
        var m = MakeupParams(); m.lipOpacity = opacity; m.blushOpacity = blush; m.lipFinish = finish; return m
    }

    static let looks: [BeautyLook] = [
        BeautyLook(id: "natural", name: "Natural", skin: SkinParams(smooth: 0.3, texture: 0.7), face: FaceReshapeParams(eyeSize: 0.1), makeup: MakeupParams(), group: "Daily"),
        BeautyLook(id: "fresh", name: "Fresh", skin: SkinParams(smooth: 0.45, texture: 0.6, whiten: 0.25), face: FaceReshapeParams(jawSlim: 0.2, eyeSize: 0.2), makeup: lips(0.25, blush: 0.2), group: "Daily"),
        BeautyLook(id: "glam", name: "Glam", skin: SkinParams(smooth: 0.6, texture: 0.5, whiten: 0.2, rosy: 0.2), face: FaceReshapeParams(jawSlim: 0.3, chinLength: 0.1, eyeSize: 0.3, noseSlim: 0.2), makeup: lips(0.5, blush: 0.35, finish: .gloss), group: "Glam"),
        BeautyLook(id: "defined", name: "Defined", skin: SkinParams(smooth: 0.35, texture: 0.75), face: FaceReshapeParams(jawSlim: 0.25, chinLength: 0.05, noseSlim: 0.1), makeup: lips(0.3), group: "Daily"),
        BeautyLook(id: "soft-glow", name: "Soft glow", skin: SkinParams(smooth: 0.55, texture: 0.55, whiten: 0.2, glow: 0.4), face: FaceReshapeParams(eyeSize: 0.12), makeup: lips(0.25, blush: 0.25), group: "Daily"),
        BeautyLook(id: "clear", name: "Clear skin", skin: SkinParams(smooth: 0.5, texture: 0.65, whiten: 0.1, even: 0.7), face: FaceReshapeParams(), makeup: MakeupParams(), group: "Daily"),
        BeautyLook(id: "bold", name: "Bold", skin: SkinParams(smooth: 0.55, texture: 0.5, whiten: 0.15, rosy: 0.1), face: FaceReshapeParams(jawSlim: 0.35, eyeSize: 0.25, noseSlim: 0.25, cheekVolume: -0.2), makeup: lips(0.65, blush: 0.3), group: "Glam"),
        BeautyLook(id: "doll", name: "Doll", skin: SkinParams(smooth: 0.7, texture: 0.45, whiten: 0.35, glow: 0.3), face: FaceReshapeParams(jawSlim: 0.3, eyeSize: 0.4, noseSlim: 0.15, mouthSize: -0.1), makeup: lips(0.4, blush: 0.4), group: "Glam"),
        BeautyLook(id: "clean-man", name: "Clean", skin: SkinParams(smooth: 0.25, texture: 0.8, matte: 0.4), face: FaceReshapeParams(), makeup: MakeupParams(), group: "Men"),
        BeautyLook(id: "sharp", name: "Sharp", skin: SkinParams(smooth: 0.2, texture: 0.85, tan: 0.15, matte: 0.3), face: FaceReshapeParams(jawSlim: -0.15, chinLength: 0.1), makeup: MakeupParams(), group: "Men"),
        BeautyLook(id: "sun", name: "Sun", skin: SkinParams(smooth: 0.3, texture: 0.75, tan: 0.3, matte: 0.2), face: FaceReshapeParams(), makeup: MakeupParams(), group: "Men"),
    ]

    /// "For you": a short list that fits a light, medium or heavy retouch taste; here simply the safest looks first.
    static func looks(in group: String) -> [BeautyLook] {
        group == "For you" ? ["natural", "fresh", "soft-glow", "clear", "clean-man"].compactMap { id in looks.first { $0.id == id } } : looks.filter { $0.group == group }
    }

    /// Scales a look from 0 (nothing) to 1 (as designed), so one slider controls the strength.
    static func scaled(_ look: BeautyLook, strength: Double) -> BeautyLook {
        let s = min(max(strength, 0), 1)
        var out = look
        out.skin.smooth *= s; out.skin.whiten *= s; out.skin.rosy *= s; out.skin.tan *= s; out.skin.even *= s; out.skin.matte *= s; out.skin.glow *= s
        out.face = FaceReshapeParams(jawSlim: look.face.jawSlim * s, chinLength: look.face.chinLength * s, eyeSize: look.face.eyeSize * s,
                                     noseSlim: look.face.noseSlim * s, mouthSize: look.face.mouthSize * s, faceWidth: look.face.faceWidth * s, cheekVolume: look.face.cheekVolume * s)
        out.makeup.lipOpacity *= s; out.makeup.blushOpacity *= s
        return out
    }
}
