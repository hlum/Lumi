import CoreImage
import Foundation
import Testing
@testable import Lumi

struct MakeupLooksTests {
    @Test func aboutTwentyUniqueLooksEachDoingSomething() {
        #expect(MakeupLooks.all.count >= 20)
        #expect(Set(MakeupLooks.all.map(\.id)).count == MakeupLooks.all.count && Set(MakeupLooks.all.map(\.name)).count == MakeupLooks.all.count)
        for l in MakeupLooks.all { #expect(!l.makeup.isIdentity || !l.eyes.isIdentity, "\(l.id)") }
    }

    @Test func everyLookHasAJapaneseName() throws {
        let ja = try #require(LocalizationTests.bundle("ja"))
        for l in MakeupLooks.all {
            let v = ja.localizedString(forKey: l.name, value: "__missing__", table: nil)
            #expect(v != "__missing__" && v != l.name || l.name == "Sakura", "no ja for \(l.name)")
        }
    }

    @Test func looksDifferFromEachOther() {
        let keys = Set(MakeupLooks.all.map { "\($0.makeup.lipColor.r),\($0.makeup.lipColor.g),\($0.makeup.blushColor.r),\($0.eyes.left.shadowColor.r)" })
        #expect(keys.count >= MakeupLooks.all.count - 2)
    }

    @Test func strengthScalesAndZeroMeansNothing() {
        let l = MakeupLooks.look("smoky")!
        let off = MakeupLooks.scaled(l, strength: 0)
        #expect(off.makeup.isIdentity && off.eyes.isIdentity)
        let half = MakeupLooks.scaled(l, strength: 0.5), full = MakeupLooks.scaled(l, strength: 1)
        #expect(abs(half.makeup.lipOpacity * 2 - full.makeup.lipOpacity) < 1e-9 && abs(half.eyes.left.shadow * 2 - full.eyes.left.shadow) < 1e-9)
        #expect(MakeupLooks.scaled(l, strength: 9).makeup == l.makeup)
        #expect(MakeupLooks.look("nope") == nil)
    }

    @Test func aLookRendersThroughTheFaceOperation() {
        var r = FaceRetouch()
        let s = MakeupLooks.scaled(MakeupLooks.look("party")!, strength: 1)
        r.makeup = s.makeup; r.eyes = s.eyes
        let img = CIImage(color: CIColor(red: 0.8, green: 0.65, blue: 0.55)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 400))
        let out = FaceRetouchRender.apply(r, to: img, faces: [EyeMakeupTests.face()])
        #expect(out.extent == img.extent && !GeometryTests.near(RendererTests.pixel(out), [0, 0, 0, 0]))
    }

    // MARK: recreate from a reference photo
    /// A painted "reference" face: known colors on the lips, cheeks and eyelids.
    static func reference() -> (CIImage, FaceInfo) {
        let f = EyeMakeupTests.face()
        var img = CIImage(color: CIColor(red: 0.85, green: 0.7, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 400))
        func paint(_ mask: CIImage?, _ c: CIColor) {
            guard let mask else { return }
            let f = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: CIImage(color: c).cropped(to: img.extent), kCIInputBackgroundImageKey: img, kCIInputMaskImageKey: mask])!
            img = f.outputImage!.cropped(to: img.extent)
        }
        paint(MakeupRenderer.lipMask(f, size: CGSize(width: 400, height: 400)), CIColor(red: 0.8, green: 0.1, blue: 0.2))
        paint(MakeupRenderer.spotsMask(MakeupRenderer.blushSpots(f, style: .round).map { MakeupRenderer.Spot(center: $0.center, radius: $0.radius * 0.5, squash: 1) }, size: CGSize(width: 400, height: 400)), CIColor(red: 1, green: 0.5, blue: 0.5))
        for r in ["leftEye", "rightEye"] { paint(EyeMakeupRenderer.shadowMask(FaceReshape.points(f, r), size: CGSize(width: 400, height: 400)), CIColor(red: 0.3, green: 0.4, blue: 0.8)) }
        return (img, f)
    }

    @Test func sampleReadsTheLipBlushAndLidColors() throws {
        let (img, face) = Self.reference()
        let c = RecreateLook.sample(img, face: face)
        let lip = try #require(c.lip), blush = try #require(c.blush), shadow = try #require(c.shadow)
        #expect(lip.r > 0.65 && lip.g < 0.3)                          // red lips
        #expect(blush.r > 0.85 && blush.g > 0.4 && blush.g < 0.65)      // pink cheeks
        #expect(shadow.b > shadow.r && shadow.b > 0.6)                   // blue lids
    }

    @Test func recreatedLooksUseTheSampledColors() throws {
        let (img, face) = Self.reference()
        let look = RecreateLook.look(from: RecreateLook.sample(img, face: face))
        #expect(look.makeup.lipOpacity > 0 && look.makeup.lipColor.r > 0.65 && look.eyes.left.shadow > 0 && look.eyes.left.shadowColor.b > 0.6)
        #expect(RecreateLook.look(from: RecreateLook.Colors()).makeup.isIdentity)
    }

    @Test func facesWithoutLandmarksGiveNoColors() {
        let c = RecreateLook.sample(CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200)), face: FaceInfo(box: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4), landmarks: [:]))
        #expect(c == RecreateLook.Colors())
    }
}
