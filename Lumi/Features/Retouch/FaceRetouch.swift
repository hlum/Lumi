import CoreImage
import Foundation
import Vision

/// Everything the Face tab can change, as one document operation.
struct FaceRetouch: Codable, Equatable {
    var skin = SkinParams()
    var reshape = FaceReshapeParams()
    var makeup = MakeupParams()
    var detail = FaceDetailParams()
    var eyes = EyeMakeup()
    var ratio = FaceRatio()
    var shape = FeatureShape()
    var blemish = BlemishParams()
    var nails = NailPaint()
    var isIdentity: Bool { nails.isIdentity && blemish.isIdentity && shape.isIdentity && ratio.isIdentity && skin.isIdentity && reshape.isIdentity && makeup.isIdentity && detail.isIdentity && eyes.isIdentity }

    init(skin: SkinParams = SkinParams(), reshape: FaceReshapeParams = FaceReshapeParams(), makeup: MakeupParams = MakeupParams(), detail: FaceDetailParams = FaceDetailParams(), eyes: EyeMakeup = EyeMakeup(), ratio: FaceRatio = FaceRatio(), shape: FeatureShape = FeatureShape(), blemish: BlemishParams = BlemishParams(), nails: NailPaint = NailPaint()) {
        self.nails = nails; self.blemish = blemish; self.shape = shape; self.ratio = ratio; self.skin = skin; self.reshape = reshape; self.makeup = makeup; self.detail = detail; self.eyes = eyes
    }
    enum CodingKeys: String, CodingKey { case skin, reshape, makeup, detail, eyes, ratio, shape, blemish, nails }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(skin: try c.decodeIfPresent(SkinParams.self, forKey: .skin) ?? SkinParams(), reshape: try c.decodeIfPresent(FaceReshapeParams.self, forKey: .reshape) ?? FaceReshapeParams(),
                  makeup: try c.decodeIfPresent(MakeupParams.self, forKey: .makeup) ?? MakeupParams(), detail: try c.decodeIfPresent(FaceDetailParams.self, forKey: .detail) ?? FaceDetailParams(),
                  eyes: try c.decodeIfPresent(EyeMakeup.self, forKey: .eyes) ?? EyeMakeup(), ratio: try c.decodeIfPresent(FaceRatio.self, forKey: .ratio) ?? FaceRatio(), shape: try c.decodeIfPresent(FeatureShape.self, forKey: .shape) ?? FeatureShape(), blemish: try c.decodeIfPresent(BlemishParams.self, forKey: .blemish) ?? BlemishParams(), nails: try c.decodeIfPresent(NailPaint.self, forKey: .nails) ?? NailPaint())
    }

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
                let regions: [(String, VNFaceLandmarkRegion2D?)] = [("leftEye", l.leftEye), ("rightEye", l.rightEye), ("nose", l.nose), ("outerLips", l.outerLips), ("innerLips", l.innerLips), ("leftEyebrow", l.leftEyebrow), ("rightEyebrow", l.rightEyebrow), ("faceContour", l.faceContour), ("leftPupil", l.leftPupil), ("rightPupil", l.rightPupil)]
                for (name, r) in regions { if let r { lm[name] = r.normalizedPoints } }
            }
            return FaceInfo(box: f.boundingBox, landmarks: lm)
        }
    }
}

enum FaceRetouchRender {
    /// Skin, makeup and detail are painted first (landmarks match the source), then the reshape warp moves it all.
    static func apply(_ r: FaceRetouch, to image: CIImage, faces: [FaceInfo]) -> CIImage {
        guard !r.isIdentity, !faces.isEmpty || !r.blemish.manual.isEmpty else { return image }
        // every mask below is built at the origin; shift a cropped or offset picture there and back so nothing lands misplaced
        let origin = image.extent.origin
        if origin != .zero {
            let there = CGAffineTransform(translationX: -origin.x, y: -origin.y)
            return apply(r, to: image.transformed(by: there), faces: faces).transformed(by: there.inverted())
        }
        var out = image
        let size = image.extent.size
        if !r.blemish.isIdentity { out = BlemishOps.apply(r.blemish, to: out, faces: faces) }       // spots go first, so smoothing never blurs them in
        for face in faces {
            if !r.skin.isIdentity, let mask = SkinMask.make(face: face, size: size, feather: 0.02) { out = SkinOps.apply(r.skin, to: out, mask: mask) }
            if !r.makeup.isIdentity { out = MakeupRenderer.apply(r.makeup, to: out, face: face) }
            if !r.detail.isIdentity { out = FaceDetailOps.apply(r.detail, to: out, face: face) }
            if r.ratio.shade3D > 0 { out = MakeupRenderer.apply(RatioRules.shading(r.ratio), to: out, face: face) }
            if !r.eyes.isIdentity { out = EyeMakeupRenderer.apply(r.eyes, to: out, face: face) }
        }
        let browWarp = (r.eyes.browShape != .natural || r.eyes.browHeight != 0) ? faces.flatMap { EyeMakeupRenderer.browStrokes($0, shape: r.eyes.browShape, height: r.eyes.browHeight) } : []
        if !r.reshape.isIdentity || r.ratio.warps || !r.shape.isIdentity || !browWarp.isEmpty {
            let aspect = Double(out.extent.width / max(out.extent.height, 1))
            var warp = WarpEdit()
            var handles: [WarpHandle] = []
            let rest = FaceHandles.remainingReshape(r.reshape), restShape = FaceHandles.remainingShape(r.shape)
            for face in faces {
                let zones = ProtectionZones.zones(face, r.ratio)
                (FaceReshape.strokes(for: face, params: rest) + FeatureRules.strokes(for: face, restShape) + RatioRules.strokes(for: face, r.ratio)).compactMap { ProtectionZones.clip($0, zones) }.forEach { warp.add($0) }
                handles += FaceHandles.handles(for: face, reshape: r.reshape, shape: r.shape, ratio: r.ratio, aspect: aspect)   // the outline and features, solved as one rigid warp
            }
            browWarp.forEach { warp.add($0) }
            var field = warp.field(aspect: Float(aspect))
            if !handles.isEmpty { field = MLSWarp.field(handles + MLSWarp.border(), aspect: aspect).adding(field) }
            out = MeshWarpRenderer.apply(field, to: out)
        }
        return out
    }
}
