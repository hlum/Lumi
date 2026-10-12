import CoreImage
import Foundation
import Testing
@testable import Lumi

struct IDPhotoRenderTests {
    private let ctx = CIContext()
    private func px(_ i: CIImage, _ x: Int, _ yDown: Int) -> [Int] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - yDown, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return b.map(Int.init)
    }
    let spec = IDSpec(id: "t", name: "t", widthMM: 35, heightMM: 45, headMin: 0.7, headMax: 0.8, eyeLine: 0.45, background: [1, 1, 1])
    /// A 1000 x 1400 photo with a 300 x 360 face in the middle, eyes at y = 480.
    let subject = IDPhotoRenderer.Subject(face: CGRect(x: 350, y: 380, width: 300, height: 360), eyeY: 480, leftEye: CGPoint(x: 450, y: 480), rightEye: CGPoint(x: 550, y: 480))
    private var photo: CIImage { CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 1400)) }
    private var person: CIImage { CIImage(color: .white).cropped(to: CGRect(x: 300, y: 0, width: 400, height: 1400)).composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 1400))) }

    @Test func outputIsExactlyTheSpecPixelsAndBackgroundReplacesTheScene() throws {
        let out = try #require(IDPhotoRenderer.render(photo, subject: subject, spec: spec, background: RGBA(r: 0.2, g: 0.4, b: 0.9, a: 1), personMask: person))
        let (w, h) = spec.pixels()
        #expect(out.extent == CGRect(x: 0, y: 0, width: w, height: h))
        let corner = px(out, 3, 3)
        #expect(corner[2] > 200 && corner[1] < 130)                     // blue, not the green scene
        let middle = px(out, w / 2, h / 2)
        #expect(middle[1] > middle[2] + 60)                             // the person (green here) stays in the middle
    }

    @Test func noMaskKeepsTheOriginalBackground() throws {
        let out = try #require(IDPhotoRenderer.render(photo, subject: subject, spec: spec, background: .white, personMask: nil))
        #expect(px(out, 10, 10)[1] > 100 && px(out, 10, 10)[0] < 120)
    }

    @Test func aFaceNearTheEdgeIsPaddedWithTheBackground() throws {
        var s = subject; s.face = CGRect(x: 20, y: 380, width: 300, height: 360); s.leftEye = CGPoint(x: 100, y: 480); s.rightEye = CGPoint(x: 200, y: 480)
        let crop = try #require(IDPhotoMath.crop(face: s.face, eyeY: s.eyeY, spec: spec, image: CGSize(width: 1000, height: 1400)))
        #expect(!crop.fitsInImage)
        let out = try #require(IDPhotoRenderer.render(photo, subject: s, spec: spec, background: RGBA(r: 1, g: 0, b: 0, a: 1), personMask: nil))
        #expect(px(out, 2, out.extent.height > 0 ? Int(out.extent.height) / 2 : 0)[0] > 200)       // left of the photo: background red
    }

    @Test func checksPassForAFramedPhotoAndFlagATiltedHead() throws {
        let ok = try #require(IDPhotoRenderer.check(subject, spec: spec, image: CGSize(width: 1000, height: 1400)))
        #expect(ok.headSizeOK && ok.centeredOK && ok.eyeLineOK && ok.levelOK && ok.passes)
        var tilted = subject; tilted.rightEye = CGPoint(x: 550, y: 560)
        #expect(IDPhotoRenderer.check(tilted, spec: spec, image: CGSize(width: 1000, height: 1400))?.levelOK == false)
    }

    @Test func subjectComesFromLandmarksInPixels() throws {
        let f = FaceReshapeTests.face()
        let s = try #require(IDPhotoRenderer.subject(from: f, imageSize: CGSize(width: 1000, height: 1000)))
        #expect(s.leftEye.x < s.rightEye.x && abs(s.face.width - 400) < 1 && s.eyeY > 300 && s.eyeY < 600)
        #expect(IDPhotoRenderer.subject(from: FaceInfo(box: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), landmarks: [:]), imageSize: CGSize(width: 10, height: 10)) == nil)
    }

    @Test func printSheetFitsCopiesOnThePaper() throws {
        let one = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 413, height: 531))
        let sheet = try #require(IDPhotoRenderer.printSheet(photo: one, spec: spec, paperMM: CGSize(width: 102, height: 152)))
        #expect(abs(sheet.extent.width - 102 * 300 / 25.4) < 1)
        let slots = IDPhotoMath.sheet(paperMM: CGSize(width: 102, height: 152), photoMM: CGSize(width: 35, height: 45))
        #expect(slots.count >= 6)
        #expect(IDPhotoRenderer.printSheet(photo: one, spec: spec, paperMM: CGSize(width: 20, height: 20)) == nil)
    }

    @Test func bundledSpecsLoadAndEveryOneHasSaneNumbers() throws {
        guard let url = Bundle.main.url(forResource: "id-specs", withExtension: "json") else { Issue.record("id-specs.json is not bundled"); return }
        let all = try IDSpec.load(Data(contentsOf: url))
        #expect(all.count >= 6)
        for s in all { #expect(s.headMin < s.headMax && s.eyeLine > 0.2 && s.eyeLine < 0.6 && s.background.count == 3 && s.widthMM > 0, "\(s.id)") }
    }
}
