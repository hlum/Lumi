import Foundation

/// One-tap looks combining skin, face reshape and makeup. Values are conservative on purpose.
struct BeautyLook: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var skin: SkinParams
    var face: FaceReshapeParams
    var makeup: MakeupParams
}

enum AutoBeauty {
    static let looks: [BeautyLook] = [
        BeautyLook(id: "natural", name: "Natural", skin: SkinParams(smooth: 0.3, texture: 0.7), face: FaceReshapeParams(eyeSize: 0.1), makeup: MakeupParams()),
        BeautyLook(id: "fresh", name: "Fresh", skin: SkinParams(smooth: 0.45, texture: 0.6, whiten: 0.25), face: FaceReshapeParams(jawSlim: 0.2, eyeSize: 0.2),
                   makeup: { var m = MakeupParams(); m.lipOpacity = 0.25; m.blushOpacity = 0.2; return m }()),
        BeautyLook(id: "glam", name: "Glam", skin: SkinParams(smooth: 0.6, texture: 0.5, whiten: 0.2, rosy: 0.2), face: FaceReshapeParams(jawSlim: 0.3, chinLength: 0.1, eyeSize: 0.3, noseSlim: 0.2),
                   makeup: { var m = MakeupParams(); m.lipOpacity = 0.5; m.lipFinish = .gloss; m.blushOpacity = 0.35; return m }()),
    ]

    /// Scales a look from 0 (nothing) to 1 (as designed), so one slider controls the strength.
    static func scaled(_ look: BeautyLook, strength: Double) -> BeautyLook {
        let s = min(max(strength, 0), 1)
        var out = look
        out.skin.smooth *= s; out.skin.whiten *= s; out.skin.rosy *= s; out.skin.tan *= s
        out.face = FaceReshapeParams(jawSlim: look.face.jawSlim * s, chinLength: look.face.chinLength * s, eyeSize: look.face.eyeSize * s,
                                     noseSlim: look.face.noseSlim * s, mouthSize: look.face.mouthSize * s, faceWidth: look.face.faceWidth * s)
        out.makeup.lipOpacity *= s; out.makeup.blushOpacity *= s
        return out
    }
}
