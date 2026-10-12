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
    /// Vision's raw names are anatomical ("left_upLeg_joint" is the hip, "left_leg_joint" the knee, "left_foot_joint" the ankle,
    /// "left_forearm_joint" the elbow); the reshape rules use the plain names below.
    static let names: [VNHumanBodyPoseObservation.JointName: String] = [
        .neck: "neck_1_joint", .root: "root",
        .leftShoulder: "left_shoulder_1_joint", .rightShoulder: "right_shoulder_1_joint",
        .leftElbow: "left_elbow_1_joint", .rightElbow: "right_elbow_1_joint",
        .leftWrist: "left_wrist_1_joint", .rightWrist: "right_wrist_1_joint",
        .leftHip: "left_hip_1_joint", .rightHip: "right_hip_1_joint",
        .leftKnee: "left_knee_1_joint", .rightKnee: "right_knee_1_joint",
        .leftAnkle: "left_ankle_1_joint", .rightAnkle: "right_ankle_1_joint",
    ]

    func poses(in image: CIImage) throws -> [[String: CGPoint]] {
        let req = VNDetectHumanBodyPoseRequest()
        try VNImageRequestHandler(ciImage: image).perform([req])
        return (req.results ?? []).map { obs in
            var out: [String: CGPoint] = [:]
            for (name, p) in (try? obs.recognizedPoints(.all)) ?? [:] where p.confidence > 0.3 { out[Self.names[name] ?? name.rawValue.rawValue] = p.location }
            return out
        }
    }
}

/// Where the person's outline is on one row of the person mask.
enum BodySilhouette {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Left and right edge (image-normalized x) of the run of person pixels that contains `centerX`, on the row `y` (y-down), or nil when that row has no person there.
    static func edges(in mask: CIImage, y: Double, centerX: Double, columns: Int = 256) -> (Double, Double)? {
        let e = mask.extent
        guard e.width > 0, e.height > 0, y >= 0, y <= 1 else { return nil }
        let row = CGRect(x: e.minX, y: e.minY + (1 - y) * e.height - 2, width: e.width, height: 4).intersection(e)
        guard !row.isNull, row.height > 0 else { return nil }
        let strip = mask.cropped(to: row).transformed(by: CGAffineTransform(translationX: -row.minX, y: -row.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(columns) / row.width, y: 1 / row.height))
        var px = [UInt8](repeating: 0, count: columns * 4)
        context.render(strip, toBitmap: &px, rowBytes: columns * 4, bounds: CGRect(x: 0, y: 0, width: columns, height: 1), format: .RGBA8, colorSpace: nil)
        return run(px.enumerated().compactMap { $0.offset % 4 == 0 ? $0.element : nil }, around: Int(min(max(centerX, 0), 1) * Double(columns - 1)))
    }

    /// The run of values above half that contains index `i`, as fractions of the row; nil when `i` is not inside one.
    static func run(_ row: [UInt8], around i: Int) -> (Double, Double)? {
        guard row.indices.contains(i), row[i] > 127 else { return nil }
        var l = i, r = i
        while l > 0, row[l - 1] > 127 { l -= 1 }
        while r < row.count - 1, row[r + 1] > 127 { r += 1 }
        return (Double(l) / Double(row.count), Double(r + 1) / Double(row.count))
    }
}

enum BodyRetouchRender {
    static func apply(_ b: BodyRetouch, to image: CIImage, poses: [[String: CGPoint]], personMask: CIImage?, inpainter: Inpainting?) -> CIImage {
        guard !b.isIdentity, !poses.isEmpty else { return image }
        var warp = WarpEdit()
        for pose in poses {
            let j = BodyReshape.joints(pose)
            let xs = ["left_shoulder_1_joint", "right_shoulder_1_joint", "left_hip_1_joint", "right_hip_1_joint"].compactMap { j[$0]?.x }
            let centre = xs.isEmpty ? 0.5 : Double(xs.reduce(0, +) / CGFloat(xs.count))
            let silhouette: ((Double) -> (Double, Double)?)? = personMask.map { m in { y in BodySilhouette.edges(in: m, y: y, centerX: centre) } }
            BodyReshape.strokes(pose: pose, params: b.params, silhouette: silhouette).forEach { warp.add($0) }
        }
        let field = warp.field(aspect: Float(image.extent.width / max(image.extent.height, 1)))
        guard !field.isIdentity else { return image }
        if b.protectBackground, let personMask { return (try? ProtectedWarp.apply(field, to: image, personMask: personMask, inpainter: inpainter)) ?? MeshWarpRenderer.apply(field, to: image) }
        return MeshWarpRenderer.apply(field, to: image)
    }
}
