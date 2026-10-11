import CoreImage
import Foundation
import Vision

/// Everything the Face tab can change, as one document operation.
struct FaceRetouch: Codable, Equatable {
    var skin = SkinParams()
    var reshape = FaceReshapeParams()
    var makeup = MakeupParams()
    var detail = FaceDetailParams()
    var isIdentity: Bool { skin.isIdentity && reshape.isIdentity && makeup.isIdentity && detail.isIdentity }

    static func look(_ l: BeautyLook, strength: Double = 1) -> FaceRetouch {
        let s = AutoBeauty.scaled(l, strength: strength)
        return FaceRetouch(skin: s.skin, reshape: s.face, makeup: s.makeup, detail: FaceDetailParams())
    }
}

/// Finds faces with landmarks. Fakeable in tests.
protocol FaceLandmarking {
    /// Faces in Vision space (normalized, origin bottom-left), with landmark regions.
    func faces(in image: CIImage) throws -> [FaceInfo]
}

struct VisionFaceLandmarker: FaceLandmarking {
    func faces(in image: CIImage) throws -> [FaceInfo] {
        let req = VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(ciImage: image).perform([req])
        return (req.results ?? []).map { f in
            var lm: [String: [CGPoint]] = [:]
            if let l = f.landmarks {
                let regions: [(String, VNFaceLandmarkRegion2D?)] = [("leftEye", l.leftEye), ("rightEye", l.rightEye), ("nose", l.nose), ("outerLips", l.outerLips), ("innerLips", l.innerLips), ("leftEyebrow", l.leftEyebrow), ("rightEyebrow", l.rightEyebrow), ("faceContour", l.faceContour)]
                for (name, r) in regions { if let r { lm[name] = r.normalizedPoints } }
            }
            return FaceInfo(box: f.boundingBox, landmarks: lm)
        }
    }
}

enum FaceRetouchRender {
    /// Skin, makeup and detail are painted first (landmarks match the source), then the reshape warp moves it all.
    static func apply(_ r: FaceRetouch, to image: CIImage, faces: [FaceInfo]) -> CIImage {
        guard !r.isIdentity, !faces.isEmpty else { return image }
        var out = image
        let size = image.extent.size
        for face in faces {
            if !r.skin.isIdentity, let mask = SkinMask.make(face: face, size: size, feather: 0.02) { out = SkinOps.apply(r.skin, to: out, mask: mask) }
            if !r.makeup.isIdentity { out = MakeupRenderer.apply(r.makeup, to: out, face: face) }
            if !r.detail.isIdentity { out = FaceDetailOps.apply(r.detail, to: out, face: face) }
        }
        if !r.reshape.isIdentity {
            var warp = WarpEdit()
            FaceReshape.strokes(for: faces, params: r.reshape).forEach { warp.add($0) }
            out = MeshWarpRenderer.apply(warp.field, to: out)
        }
        return out
    }
}
