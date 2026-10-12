import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Everything the Body tab can change, as one document operation.
struct BodyRetouch: Codable, Equatable {
    var params = BodyReshapeParams()
    var protectBackground = true       // keep walls and lines where they were and fill the strip the body leaves

    var isIdentity: Bool { params.isIdentity }

    init() {}
    enum CodingKeys: String, CodingKey { case params, protectBackground }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        params = try c.decodeIfPresent(BodyReshapeParams.self, forKey: .params) ?? BodyReshapeParams()
        protectBackground = try c.decodeIfPresent(Bool.self, forKey: .protectBackground) ?? true
    }
}

/// Finds body poses: joints by Vision's raw names, image-normalized with a bottom-left origin.
protocol BodyFinding { func poses(in image: CIImage) throws -> [[String: CGPoint]] }

struct VisionBodyFinder: BodyFinding {
    func poses(in image: CIImage) throws -> [[String: CGPoint]] {
        let req = VNDetectHumanBodyPoseRequest()
        try VNImageRequestHandler(ciImage: image).perform([req])
        return (req.results ?? []).map { obs in
            var out: [String: CGPoint] = [:]
            for (name, p) in (try? obs.recognizedPoints(.all)) ?? [:] where p.confidence > 0.3 { out[name.rawValue.rawValue] = p.location }
            return out
        }
    }
}

enum BodyRetouchRender {
    static func apply(_ b: BodyRetouch, to image: CIImage, poses: [[String: CGPoint]], personMask: CIImage?, inpainter: Inpainting?) -> CIImage {
        guard !b.isIdentity, !poses.isEmpty else { return image }
        var warp = WarpEdit()
        BodyReshape.strokes(poses: poses, params: b.params).forEach { warp.add($0) }
        let field = warp.field
        guard !field.isIdentity else { return image }
        if b.protectBackground, let personMask { return (try? ProtectedWarp.apply(field, to: image, personMask: personMask, inpainter: inpainter)) ?? MeshWarpRenderer.apply(field, to: image) }
        return MeshWarpRenderer.apply(field, to: image)
    }
}
