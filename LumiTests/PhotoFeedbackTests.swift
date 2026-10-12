import CoreImage
import Testing
@testable import Lumi

@Suite(.serialized)
struct PhotoFeedbackTests {
    static let rect = CGRect(x: 0, y: 0, width: 128, height: 128)

    /// A person facing the camera: Vision's "left" joints sit on the image's right.
    static func facing() -> [String: CGPoint] {
        [
            "neck_1_joint": CGPoint(x: 0.5, y: 0.85),
            "left_shoulder_1_joint": CGPoint(x: 0.6, y: 0.8), "right_shoulder_1_joint": CGPoint(x: 0.4, y: 0.8),
            "left_hip_1_joint": CGPoint(x: 0.56, y: 0.5), "right_hip_1_joint": CGPoint(x: 0.44, y: 0.5),
            "left_knee_1_joint": CGPoint(x: 0.56, y: 0.3), "right_knee_1_joint": CGPoint(x: 0.44, y: 0.3),
            "left_ankle_1_joint": CGPoint(x: 0.56, y: 0.1), "right_ankle_1_joint": CGPoint(x: 0.44, y: 0.1),
        ]
    }

    @Test func waistAndHipsPushTowardTheMiddleWhicheverSideVisionCallsLeft() {
        for key in [BodyReshapeParams.Key.waist, .hips, .legSlim, .thighs, .calves] {
            var p = BodyReshapeParams(); p[keyPath: key.path] = 1
            let s = BodyReshape.strokes(pose: Self.facing(), params: p)
            #expect(!s.isEmpty)
            for st in s { #expect((st.x < 0.5 && st.dirX > 0) || (st.x > 0.5 && st.dirX < 0), "\(key) stroke at \(st.x) moves \(st.dirX)") }
        }
    }

    @Test func torsoStrokesSitOnTheSilhouetteWhenTheMaskKnowsIt() {
        var p = BodyReshapeParams(); p.waist = 1
        let s = BodyReshape.strokes(pose: Self.facing(), params: p, silhouette: { _ in (0.3, 0.7) })
        #expect(s.count == 2 && Set(s.map { Float($0.x) }) == [0.3, 0.7])
    }

    @Test func silhouetteRunIsTheStretchContainingTheCentre() {
        let row: [UInt8] = [0, 0, 255, 255, 255, 0, 255, 255]
        let r = BodySilhouette.run(row, around: 3)
        #expect(r?.0 == 0.25 && r?.1 == 0.625)
        #expect(BodySilhouette.run(row, around: 0) == nil)
    }

    @Test func silhouetteIsReadFromARealMask() {
        let mask = MosaicOps.mask(rects: [CGRect(x: 0.25, y: 0, width: 0.5, height: 1)], extent: Self.rect)
        let e = BodySilhouette.edges(in: mask, y: 0.5, centerX: 0.5)
        #expect(e != nil && abs(e!.0 - 0.25) < 0.02 && abs(e!.1 - 0.75) < 0.02)
    }

    @Test func slimmingWaistNarrowsTheBodyInTheRender() {
        let bg = CIImage(color: CIColor(red: 0.2, green: 0.2, blue: 0.2)).cropped(to: Self.rect)
        let body = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(x: 44, y: 0, width: 40, height: 128)).composited(over: bg)
        var b = BodyRetouch(); b.params.waist = 1; b.protectBackground = false
        let out = BodyRetouchRender.apply(b, to: body, poses: [Self.facing()], personMask: MosaicOps.mask(rects: [CGRect(x: 44.0 / 128, y: 0, width: 40.0 / 128, height: 1)], extent: Self.rect), inpainter: nil)
        func width(_ img: CIImage) -> Int { (0..<128).filter { GeometryTests.rgb(img, x: $0, y: 79)[0] > 150 }.count }   // the waist, 38% down from the top
        #expect(width(out) < width(body) - 2, "waist \(width(body)) -> \(width(out))")
    }

    @Test func brushCirclesStayRoundOnWidePhotos() {
        var f = DisplacementField(cols: 65, rows: 65)
        f.apply(BrushStroke(kind: .push, x: 0.5, y: 0.5, radius: 0.2, strength: 1, dirX: 0.1, dirY: 0), aspect: 2)   // twice as wide as tall
        // the circle is 0.2 of the width wide, which is 0.4 of the height: reaches 0.3 down, not 0.45
        #expect(f.offset(x: 0.65, y: 0.5).0 != 0)
        #expect(f.offset(x: 0.5, y: 0.8).0 != 0)
        #expect(f.offset(x: 0.5, y: 0.95).0 == 0)
    }

    @Test func smoothingDoesNotBrightenSkin() {
        let tone = CIImage(color: CIColor(red: 0.55, green: 0.38, blue: 0.3)).cropped(to: Self.rect)
        // speckled skin: dark and light pores around the same average
        var speckle = tone
        for i in 0..<40 {
            let c: CIColor = i % 2 == 0 ? CIColor(red: 0.3, green: 0.2, blue: 0.15) : CIColor(red: 0.8, green: 0.6, blue: 0.5)
            speckle = CIImage(color: c).cropped(to: CGRect(x: (i * 37) % 120, y: (i * 53) % 120, width: 5, height: 5)).composited(over: speckle)
        }
        var p = SkinParams(); p.smooth = 1
        let out = SkinOps.apply(p, to: speckle, mask: CIImage(color: .white).cropped(to: Self.rect))
        func mean(_ img: CIImage) -> Double {
            let a = img.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: Self.rect)])
            var px = [UInt8](repeating: 0, count: 4)
            CIContext().render(a, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return (Double(px[0]) + Double(px[1]) + Double(px[2])) / 3
        }
        #expect(mean(out) - mean(speckle) < 6, "smooth moved the average from \(mean(speckle)) to \(mean(out))")
    }

    @Test func zoomPanStaysInsideThePicture() {
        let size = CGSize(width: 300, height: 400)
        #expect(ZoomBridge.clamped(CGSize(width: 900, height: -900), zoom: 2, in: size) == CGSize(width: 150, height: -200))
        #expect(ZoomBridge.clamped(CGSize(width: 50, height: 50), zoom: 1, in: size) == .zero)
    }

    @Test func smallFeaturesAreNotOutlined() {
        for m in [FaceMark.eyes, .brows, .nose, .mouth] { #expect(!m.isDrawn) }
        for m in [FaceMark.jaw, .chin, .faceWidth, .face, .cheeks, .lift] { #expect(m.isDrawn) }
    }

    @Test func onlyHeavyEditsGetABackgroundPreview() {
        var d = EditDocument()
        #expect(!d.needsSlowPreview)
        d.body.params.waist = 0.5; d.body.protectBackground = false
        #expect(!d.needsSlowPreview)
        d.body.protectBackground = true
        #expect(d.needsSlowPreview && !d.withoutSlowOps.needsSlowPreview)
        d.adjust.exposure = 0.3
        #expect(d.withoutSlowOps.operations.count == 1)
    }

    @MainActor @Test func previewMatchesTheExportOnceTheSlowRenderLands() async throws {
        let model = EditorModel()
        let img = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: Self.rect)
        model.load(image: img)
        model.draft.body.params.waist = 0.5
        _ = model.preview
        // the slow render may load the matting model first, which takes a while
        for _ in 0..<120 where model.slowImage == nil || model.isRendering { try await Task.sleep(for: .milliseconds(500)) }
        #expect(!model.isRendering && model.slowImage != nil)
        #expect(model.preview?.extent == model.slowImage?.extent)
    }

    @Test func aWarpStrokeLandsWhereItWasPlacedVertically() {
        // y-down 0.8 is near the bottom of the picture, which is a small y in Core Image
        let ramp = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 100, y: 0), "inputColor0": CIColor.black, "inputColor1": CIColor.white])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
        var e = WarpEdit(cols: 49, rows: 49)
        e.add(BrushStroke(kind: .push, x: 0.5, y: 0.8, radius: 0.15, strength: 1, dirX: 0.1, dirY: 0))
        let out = MeshWarpRenderer.apply(e.field(aspect: 0.5), to: ramp)
        let changed = (0..<200).filter { y in abs(Int(GeometryTests.rgb(out, x: 50, y: y)[0]) - Int(GeometryTests.rgb(ramp, x: 50, y: y)[0])) > 6 }
        let centre = Double(changed.reduce(0, +)) / Double(max(changed.count, 1))
        #expect(!changed.isEmpty && abs(centre - 40) < 15, "changed rows centre at CI y \(centre) (expected near 40)")
    }
}

/// Vision's joint names are anatomical; the reshape rules must get every joint they ask for.
struct BodyJointNameTests {
    @Test func everyJointTheRulesUseComesOutOfVision() {
        let given = Set(VisionBodyFinder.names.values)
        for n in ["left_hip_1_joint", "right_hip_1_joint", "left_knee_1_joint", "right_knee_1_joint", "left_ankle_1_joint", "right_ankle_1_joint",
                  "left_elbow_1_joint", "right_elbow_1_joint", "left_shoulder_1_joint", "right_shoulder_1_joint", "neck_1_joint"] { #expect(given.contains(n), "\(n)") }
        #expect(VisionBodyFinder.names[.leftHip] == "left_hip_1_joint" && VisionBodyFinder.names[.leftKnee] == "left_knee_1_joint")
    }
}
