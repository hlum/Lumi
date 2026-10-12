import CoreImage
import Foundation
import Testing
@testable import Lumi

struct RetouchDetailTests {
    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private let face = FaceReshapeTests.face()
    private let side: CGFloat = 400

    private func px(_ i: CIImage, _ nx: Double, _ ny: Double) -> [Int] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: Int(nx * Double(side)), y: Int((1 - ny) * Double(side)), width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return b.map(Int.init)
    }
    private func skin() -> CIImage { CIImage(color: CIColor(red: 0.8, green: 0.62, blue: 0.52)).cropped(to: CGRect(x: 0, y: 0, width: side, height: side)) }
    private func dot(_ nx: Double, _ ny: Double, r: CGFloat, color: CIColor, on img: CIImage) -> CIImage {
        let g = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(x: CGFloat(nx) * side, y: CGFloat(1 - ny) * side), "inputRadius0": r, "inputRadius1": r + 0.5, "inputColor0": color, "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)])!.outputImage!
        return g.composited(over: img).cropped(to: img.extent)
    }
    private func diff(_ a: CIImage, _ b: CIImage, _ nx: Double, _ ny: Double) -> Int { zip(px(a, nx, ny), px(b, nx, ny)).map { abs($0 - $1) }.reduce(0, +) }

    // MARK: details

    @Test func contactsRecolourTheIrisOnly() {
        var d = FaceDetailParams(); d.contactAmount = 1; d.contactColor = RGBA(r: 0.1, g: 0.4, b: 1, a: 1)
        let eye = FaceReshape.center(FaceReshape.points(face, "leftEye"))!
        let base = dot(Double(eye.x), Double(eye.y), r: 6, color: CIColor(red: 0.12, green: 0.08, blue: 0.05), on: skin())
        let out = FaceDetailOps.apply(d, to: base, face: face)
        #expect(px(out, Double(eye.x), Double(eye.y))[2] > px(base, Double(eye.x), Double(eye.y))[2] + 30)     // bluer at the iris
        #expect(diff(out, base, 0.5, 0.9) == 0)                                                                   // far from the eyes: untouched
    }

    @Test func catchlightAddsAHighlightNextToTheCenter() {
        var d = FaceDetailParams(); d.catchlight = 1
        let eye = FaceReshape.center(FaceReshape.points(face, "leftEye"))!
        let base = CIImage(color: CIColor(red: 0.1, green: 0.08, blue: 0.06)).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        let out = FaceDetailOps.apply(d, to: base, face: face)
        let w = Double(FaceReshape.width(FaceReshape.points(face, "leftEye")))
        #expect(px(out, Double(eye.x) - w * 0.07, Double(eye.y) - w * 0.07)[0] > 100)       // a small highlight, a couple of pixels wide at this size
        #expect(px(out, Double(eye.x) + w * 0.4, Double(eye.y) + w * 0.4)[0] < 40)
    }

    @Test func eyeBagsAndTroughsOnlyTouchTheirOwnPlace() {
        let eye = FaceReshape.center(FaceReshape.points(face, "leftEye"))!
        let w = Double(FaceReshape.width(FaceReshape.points(face, "leftEye")))
        var textured = skin()
        for i in 0..<12 { textured = dot(Double(eye.x) + Double(i % 4 - 2) * 0.012, Double(eye.y) + w * 0.5 + Double(i / 4) * 0.012, r: 2, color: CIColor(red: 0.5, green: 0.35, blue: 0.3), on: textured) }
        var bags = FaceDetailParams(); bags.eyeBags = 1
        let out = FaceDetailOps.apply(bags, to: textured, face: face)
        #expect(diff(out, textured, Double(eye.x), Double(eye.y) + w * 0.5) > 0)
        #expect(diff(out, textured, 0.5, 0.9) == 0)
        var trough = FaceDetailParams(); trough.tearTroughs = 1
        #expect(FaceDetailOps.tearTroughMask(face, size: CGSize(width: side, height: side)) != nil && !trough.isIdentity)
    }

    @Test func smileAndEyeLinesSplitTheOldWrinkleSlider() {
        let size = CGSize(width: side, height: side)
        func area(_ m: CIImage?) -> Int {
            guard let m else { return 0 }
            var total = 0
            for y in stride(from: 0, to: 400, by: 10) { for x in stride(from: 0, to: 400, by: 10) {
                var b = [UInt8](repeating: 0, count: 4)
                ctx.render(m, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
                total += Int(b[0]) > 128 ? 1 : 0
            } }
            return total
        }
        let eyes = area(FaceDetailOps.wrinkleMask(face, size: size, eyes: true, mouth: false)), mouth = area(FaceDetailOps.wrinkleMask(face, size: size, eyes: false, mouth: true))
        let both = area(FaceDetailOps.wrinkleMask(face, size: size))
        #expect(eyes > 0 && mouth > 0 && abs(both - (eyes + mouth)) <= max(2, both / 10))
    }

    @Test func oldDetailDraftsDecode() throws {
        let old = #"{"flash":0.2,"underEye":0.3,"wrinkles":0,"teethWhiten":0.5,"eyeBright":0}"#
        let d = try JSONDecoder().decode(FaceDetailParams.self, from: Data(old.utf8))
        #expect(d.flash == 0.2 && d.teethWhiten == 0.5 && d.contactAmount == 0 && !d.isIdentity)
        var n = FaceDetailParams(); n.contactAmount = 0.5; n.catchlight = 0.3
        #expect(try JSONDecoder().decode(FaceDetailParams.self, from: JSONEncoder().encode(n)) == n)
    }

    // MARK: blemishes

    @Test func autoSpotsHealADarkSpotButLeaveTheEyesAlone() {
        var img = dot(0.37, 0.64, r: 4, color: CIColor(red: 0.35, green: 0.22, blue: 0.2), on: skin())
        let eye = FaceReshape.center(FaceReshape.points(face, "leftEye"))!
        img = dot(Double(eye.x), Double(eye.y), r: 5, color: CIColor(red: 0.1, green: 0.07, blue: 0.05), on: img)
        var p = BlemishParams(); p.spots = 1
        let out = BlemishOps.apply(p, to: img, faces: [face])
        let found = BlemishOps.detect(in: img, face: face, sensitivity: 1)
        #expect(px(img, 0.37, 0.64)[0] < 120 && px(out, 0.37, 0.64)[0] > 170, "found \(found) out \(px(out, 0.37, 0.64))")       // spot gone
        #expect(diff(out, img, Double(eye.x), Double(eye.y)) < 10)                                   // pupil stays dark
    }

    @Test func tappedSpotsHealEvenWithoutAFace() {
        let img = dot(0.3, 0.3, r: 5, color: CIColor(red: 0.3, green: 0.2, blue: 0.2), on: skin())
        var f = FaceRetouch(); f.blemish.manual = [HealSpot(x: 0.3, y: 0.3, r: 0.02)]
        let out = FaceRetouchRender.apply(f, to: img, faces: [])
        #expect(px(out, 0.3, 0.3)[0] > px(img, 0.3, 0.3)[0] + 60)
    }

    @Test func rednessCalmsRedSkinOnly() {
        let red = CIImage(color: CIColor(red: 0.95, green: 0.35, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        var p = BlemishParams(); p.redness = 1
        let out = BlemishOps.apply(p, to: red, faces: [face])
        let before = px(red, 0.5, 0.5), after = px(out, 0.5, 0.5)
        #expect((after[0] - after[1]) < (before[0] - before[1]) - 30)
        let neutral = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
        #expect(diff(BlemishOps.apply(p, to: neutral, faces: [face]), neutral, 0.5, 0.5) < 4)
    }

    @Test func blemishDraftsRoundTripAndOldOnesDecode() throws {
        var p = BlemishParams(); p.spots = 0.5; p.manual = [HealSpot(x: 0.1, y: 0.2, r: 0.01)]
        #expect(try JSONDecoder().decode(BlemishParams.self, from: JSONEncoder().encode(p)) == p)
        #expect(try JSONDecoder().decode(FaceRetouch.self, from: Data("{}".utf8)).blemish.isIdentity)
        #expect(!p.isIdentity && BlemishParams().isIdentity)
    }
}
