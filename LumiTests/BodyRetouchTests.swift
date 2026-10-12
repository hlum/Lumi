import CoreImage
import Foundation
import Testing
@testable import Lumi

struct BodyRetouchTests {
    /// A standing figure facing the camera (Vision space: y up, 0...1).
    static func pose() -> [String: CGPoint] {
        ["left_shoulder_1_joint": CGPoint(x: 0.4, y: 0.8), "right_shoulder_1_joint": CGPoint(x: 0.6, y: 0.8),
         "left_hip_1_joint": CGPoint(x: 0.43, y: 0.5), "right_hip_1_joint": CGPoint(x: 0.57, y: 0.5),
         "left_knee_1_joint": CGPoint(x: 0.42, y: 0.3), "right_knee_1_joint": CGPoint(x: 0.58, y: 0.3),
         "left_ankle_1_joint": CGPoint(x: 0.41, y: 0.08), "right_ankle_1_joint": CGPoint(x: 0.59, y: 0.08),
         "left_elbow_1_joint": CGPoint(x: 0.35, y: 0.65), "right_elbow_1_joint": CGPoint(x: 0.65, y: 0.65), "neck_1_joint": CGPoint(x: 0.5, y: 0.85)]
    }
    struct Poses: BodyFinding { var all: [[String: CGPoint]]; func poses(in image: CIImage) throws -> [[String: CGPoint]] { all } }
    private func strokes(_ k: BodyReshapeParams.Key, _ v: Double) -> [BrushStroke] { var p = BodyReshapeParams(); p[keyPath: k.path] = v; return BodyReshape.strokes(pose: Self.pose(), params: p) }

    @Test func everyBodySliderMovesSomethingAndZeroMovesNothing() {
        for k in BodyReshapeParams.Key.allCases { #expect(!strokes(k, 0.8).isEmpty, "\(k)"); #expect(strokes(k, 0).isEmpty, "\(k)") }
    }

    @Test func thighAndCalfSlimmingSqueezeTheirOwnSegmentsInward() {
        for (k, lo, hi) in [(BodyReshapeParams.Key.thighs, 0.5, 0.7), (.calves, 0.7, 0.92)] {            // y-down bands: hip-knee, knee-ankle
            let s = strokes(k, 1)
            #expect(s.count == 2)
            let left = s.min { $0.x < $1.x }!, right = s.max { $0.x < $1.x }!
            #expect(left.dirX > 0 && right.dirX < 0, "\(k)")
            #expect(s.allSatisfy { Double($0.y) > lo - 1e-6 && Double($0.y) < hi + 1e-6 }, "\(k)")
        }
    }

    @Test func straightenPullsKneesTowardTheHipAnkleLine() {
        var p = BodyReshapeParams(); p.legStraighten = 1
        let s = BodyReshape.strokes(pose: Self.pose(), params: p)
        #expect(s.count == 2 && s.allSatisfy { $0.kind == .push })
    }

    @Test func draftsRoundTripAndOldOnesDecode() throws {
        var b = BodyRetouch(); b.params.waist = 0.4; b.params.calves = -0.2; b.protectBackground = false
        #expect(try JSONDecoder().decode(BodyRetouch.self, from: JSONEncoder().encode(b)) == b)
        let old = try JSONDecoder().decode(BodyReshapeParams.self, from: Data(#"{"waist":0.3,"legLength":0.1}"#.utf8))
        #expect(old.waist == 0.3 && old.thighs == 0)
        #expect(try JSONDecoder().decode(BodyRetouch.self, from: Data("{}".utf8)).isIdentity)
        var d = EditDocument(); d.body = b
        #expect(d.operations.count == 1 && d.body == b)
        d.body = BodyRetouch(); #expect(d.operations.isEmpty)
    }

    @Test func renderWarpsThePictureOnlyWhenAPoseIsFound() {
        let img = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 400))
        let saved = Renderer.services.bodyFinder; let savedMask = Renderer.services.subjectMasker
        defer { Renderer.services.bodyFinder = saved; Renderer.services.subjectMasker = savedMask }
        Renderer.services.subjectMasker = nil
        var d = EditDocument(); d.body.params.waist = 1; d.body.protectBackground = false
        Renderer.services.bodyFinder = Poses(all: [])
        #expect(Renderer.render(img, document: d).extent == img.extent)
        Renderer.services.bodyFinder = Poses(all: [Self.pose()])
        #expect(Renderer.render(img, document: d).extent == img.extent)
        #expect(BodyRetouchRender.apply(BodyRetouch(), to: img, poses: [Self.pose()], personMask: nil, inpainter: nil) == img)
    }
}
