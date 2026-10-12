import CoreGraphics
import Testing
@testable import Lumi

struct FaceMarksTests {
    let face = FaceReshapeTests.face()

    private func points(_ shapes: [MarkShape]) -> [CGPoint] {
        shapes.flatMap { s -> [CGPoint] in
            switch s {
            case .line(let p, _): p
            case .ellipse(let c, let rx, let ry): [CGPoint(x: c.x - rx, y: c.y - ry), CGPoint(x: c.x + rx, y: c.y + ry)]
            }
        }
    }

    @Test func everyMarkProducesShapesOnAFullFaceInsideThePicture() {
        let all: [FaceMark] = [.face, .skin, .jaw, .chin, .faceWidth, .lift, .eyes, .brows, .nose, .mouth, .lips, .teeth, .cheeks, .blush, .contour, .highlight, .underEye]
        // the synthetic face has no brows or inner lips, so those two are allowed to be empty
        for m in all where ![.brows, .teeth].contains(m) {
            let s = FaceMarks.shapes(m, face: face, aspect: 1)
            #expect(!s.isEmpty, "\(m)")
            for p in points(s) { #expect(p.x > -0.2 && p.x < 1.2 && p.y > -0.2 && p.y < 1.2, "\(m)") }
        }
    }

    @Test func jawMarkCoversOnlyTheLowerFaceAndChinIsTheBottom() {
        let contour = FaceReshape.points(face, "faceContour")
        let lo = contour.map(\.y).max()!, hi = contour.map(\.y).min()!
        let jaw = points(FaceMarks.shapes(.jaw, face: face, aspect: 1))
        #expect(!jaw.isEmpty && jaw.allSatisfy { $0.y - hi > (lo - hi) * 0.35 - 1e-9 })
        let chin = points(FaceMarks.shapes(.chin, face: face, aspect: 1))
        #expect(chin.count == 5 && chin.contains { abs($0.y - lo) < 1e-9 })
        #expect(points(FaceMarks.shapes(.faceWidth, face: face, aspect: 1)).count == contour.count)
    }

    @Test func eyeMarksSurroundTheEyesAndStayApart() {
        let shapes = FaceMarks.shapes(.eyes, face: face, aspect: 1)
        #expect(shapes.count == 2)
        let l = FaceReshape.center(FaceReshape.points(face, "leftEye"))!, r = FaceReshape.center(FaceReshape.points(face, "rightEye"))!
        if case .line(let p, let closed) = shapes[0] { #expect(closed && abs(FaceReshape.center(p)!.x - l.x) < 1e-6) }
        if case .line(let p, _) = shapes[1] { #expect(abs(FaceReshape.center(p)!.x - r.x) < 1e-6) }
    }

    @Test func makeupSpotsBecomeEllipsesSizedByTheImageAspect() {
        let square = FaceMarks.shapes(.blush, face: face, aspect: 1), wide = FaceMarks.shapes(.blush, face: face, aspect: 2)
        guard case .ellipse(_, let rx1, let ry1) = square[0], case .ellipse(_, let rx2, let ry2) = wide[0] else { Issue.record("expected ellipses"); return }
        #expect(rx1 == rx2 && abs(ry2 - 2 * ry1) < 1e-9)
    }

    @Test func noLandmarksMeansNoMarks() {
        let bare = FaceInfo(box: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4), landmarks: [:])
        for m in [FaceMark.jaw, .eyes, .lips, .nose, .skin] { #expect(FaceMarks.shapes(m, face: bare, aspect: 1).isEmpty, "\(m)") }
        #expect(!FaceMarks.shapes(.face, face: bare, aspect: 1).isEmpty)       // the box needs no landmarks
    }
}
