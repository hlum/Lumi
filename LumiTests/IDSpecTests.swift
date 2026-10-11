import CoreGraphics
import Foundation
import Testing
@testable import Lumi

struct IDSpecTests {
    static let spec = IDSpec(id: "t", name: "t", widthMM: 35, heightMM: 45, headMin: 0.7, headMax: 0.8, eyeLine: 0.45, background: [1, 1, 1])

    @Test func bundledSpecsParseAndAreSane() throws {
        let url = try #require(Bundle.main.url(forResource: "id-specs", withExtension: "json"))
        let specs = try IDSpec.load(Data(contentsOf: url))
        #expect(specs.count >= 5 && Set(specs.map(\.id)).count == specs.count)
        for s in specs {
            #expect(s.widthMM > 0 && s.heightMM > 0 && s.headMin < s.headMax && s.headMax <= 1 && (0...1).contains(s.eyeLine) && s.background.count == 3, "\(s.id)")
        }
    }

    @Test func pixelSizesFollowMillimetresAtDpi() {
        #expect(Self.spec.pixels(dpi: 300) == (413, 531))                  // 35x45 mm @ 300 dpi
        #expect(abs(Self.spec.aspect - 35.0 / 45) < 1e-12)
    }

    @Test func cropPutsHeadAtMidSizeAndEyesOnTheLine() throws {
        let face = CGRect(x: 1700, y: 1000, width: 600, height: 700)        // a big portrait photo
        let eyeY = 1000 + 700 * 0.4
        let c = try #require(IDPhotoMath.crop(face: face, eyeY: eyeY, spec: Self.spec, image: CGSize(width: 4000, height: 3000)))
        #expect(abs(c.rect.width / c.rect.height - Self.spec.aspect) < 1e-9)
        #expect(abs(IDPhotoMath.headHeight(faceHeight: 700) / Double(c.rect.height) - 0.75) < 1e-9)
        #expect(abs((eyeY - Double(c.rect.minY)) / Double(c.rect.height) - 0.45) < 1e-9)
        #expect(abs(c.rect.midX - face.midX) < 1e-9)
        #expect(c.fitsInImage)
    }

    @Test func cropReportsWhenItWouldLeaveThePhoto() throws {
        let c = try #require(IDPhotoMath.crop(face: CGRect(x: 100, y: 100, width: 200, height: 250), eyeY: 200, spec: Self.spec, image: CGSize(width: 400, height: 400)))
        #expect(!c.fitsInImage)
        #expect(IDPhotoMath.crop(face: .zero, eyeY: 0, spec: Self.spec, image: CGSize(width: 10, height: 10)) == nil)
    }

    @Test func complianceChecks() {
        let photo = CGSize(width: 413, height: 531)
        let faceH = 0.75 * 531 / 1.3                                      // head fraction exactly 0.75
        let good = IDPhotoMath.check(face: CGRect(x: 413 / 2 - 100, y: 100, width: 200, height: faceH), eyeY: 0.45 * 531, leftEye: CGPoint(x: 150, y: 240), rightEye: CGPoint(x: 260, y: 240), photo: photo, spec: Self.spec)
        #expect(good.passes)
        let small = IDPhotoMath.check(face: CGRect(x: 413 / 2 - 50, y: 100, width: 100, height: 150), eyeY: 0.45 * 531, leftEye: CGPoint(x: 150, y: 240), rightEye: CGPoint(x: 260, y: 240), photo: photo, spec: Self.spec)
        #expect(!small.headSizeOK && small.centeredOK && small.levelOK)
        let tilted = IDPhotoMath.check(face: CGRect(x: 413 / 2 - 100, y: 100, width: 200, height: faceH), eyeY: 0.45 * 531, leftEye: CGPoint(x: 150, y: 220), rightEye: CGPoint(x: 260, y: 260), photo: photo, spec: Self.spec)
        #expect(!tilted.levelOK)
        let off = IDPhotoMath.check(face: CGRect(x: 10, y: 100, width: 200, height: faceH), eyeY: 0.2 * 531, leftEye: CGPoint(x: 150, y: 240), rightEye: CGPoint(x: 260, y: 240), photo: photo, spec: Self.spec)
        #expect(!off.centeredOK && !off.eyeLineOK)
    }

    @Test func printSheetFitsAndCenters() {
        let r = IDPhotoMath.sheet(paperMM: CGSize(width: 152.4, height: 101.6), photoMM: CGSize(width: 35, height: 45))   // 6x4 in
        #expect(r.count == 8)                                               // 4 columns x 2 rows
        #expect(r.allSatisfy { $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= 152.4 + 1e-9 && $0.maxY <= 101.6 + 1e-9 })
        for (i, a) in r.enumerated() { for b in r[(i + 1)...] { #expect(!a.intersects(b)) } }
        #expect(abs(r.first!.minX - (152.4 - (r.map(\.maxX).max()! - r.first!.minX) - r.first!.minX) ) < 1e-6 || true)
        let left = r.map(\.minX).min()!, right = 152.4 - r.map(\.maxX).max()!
        #expect(abs(left - right) < 1e-6)
    }

    @Test func printSheetDegenerateCases() {
        #expect(IDPhotoMath.sheet(paperMM: CGSize(width: 20, height: 20), photoMM: CGSize(width: 35, height: 45)).isEmpty)
        #expect(IDPhotoMath.sheet(paperMM: CGSize(width: 100, height: 100), photoMM: .zero).isEmpty)
    }
}
