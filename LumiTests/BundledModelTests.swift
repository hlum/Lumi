import CoreImage
import CoreML
import Testing
@testable import Lumi

@Suite(.serialized)
struct BundledModelTests {
    static let rect = CGRect(x: 0, y: 0, width: 256, height: 192)

    @Test func newDefaultsAreMappedAndBundled() {
        let hair = ModelEntry.bundledDefaults.first { $0.id == "face-parsing" }, matte = ModelEntry.bundledDefaults.first { $0.id == "birefnet-lite" }
        #expect(hair?.slot == .hairSegmentation && hair?.classIndex == 17 && hair?.units == "cpuOnly" && hair?.missingRoles.isEmpty == true)
        #expect(matte?.slot == .personMatting && matte?.normalize == "imagenet" && matte?.units == "cpuOnly" && matte?.missingRoles.isEmpty == true)
        #expect(ModelStore.shared.isAvailable(.hairSegmentation) && ModelStore.shared.isAvailable(.personMatting))
    }

    @Test func classMapsBecomeMasksAndProbabilitiesStayProbabilities() throws {
        let classes = try MLMultiArray(shape: [1, 2, 2], dataType: .float32)
        for (i, v) in [0, 17, 17, 3].enumerated() { classes[i] = NSNumber(value: v) }
        #expect(MaskModelOutput.plane(classes, classIndex: 17)?.bytes == [0, 255, 255, 0])
        let logits = try MLMultiArray(shape: [1, 1, 2, 2], dataType: .float16)
        for (i, v) in [-8, 8, 0, 8].enumerated() { logits[i] = NSNumber(value: v) }
        let p = MaskModelOutput.plane(logits, classIndex: nil)
        #expect(p?.bytes[0] == 0 && p?.bytes[1] == 255 && p?.bytes[2] == 128 && p?.width == 2)
    }

    @Test func headWindowIsASquareAboveTheFaceCentre() {
        let w = ModelHairMasker.window(forFace: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        #expect(abs(w.width - w.height) < 0.001 && abs(w.width - 460) < 1)
        #expect(w.midY > 500 && abs(w.midX - 500) < 1)                   // y-up: the window sits above the face centre
    }

    @Test func matteInputIsImageNetNormalisedChannelFirst() throws {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32BGRA, nil, &pb)
        CIContext().render(CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4)), to: pb!)
        let a = try ModelSubjectMasker.array(from: pb!, side: 4)
        #expect(a.shape.map(\.intValue) == [1, 3, 4, 4])
        #expect(abs(a[0].floatValue - (1 - 0.485) / 0.229) < 0.05)       // red channel plane first
        #expect(abs(a[16].floatValue - (0 - 0.456) / 0.224) < 0.05)      // then green
    }

    @Test func mainThreadCacheMissesAreNotedNotRun() async {
        let s = Renderer.Services()
        s.deferMissesOnMain = true
        var ran = false
        let r = await MainActor.run { s.cached("k") { ran = true; return CIImage(color: .white) } }
        s.deferMissesOnMain = false
        #expect(r == nil && !ran && s.missedOnMain)
        #expect(s.cached("k") { CIImage(color: .white).cropped(to: Self.rect) } != nil)
    }

    @Test func hairModelRunsOnAPhotoSizedImage() throws {
        let img = CIImage(color: CIColor(red: 0.6, green: 0.5, blue: 0.4)).cropped(to: Self.rect)
        let masks = try ModelHairMasker(faces: nil).hairMasks(in: img)
        #expect(masks.count == 1 && masks[0].extent == Self.rect)
    }

    @Test func mattingModelRunsAndEitherFindsASubjectOrNone() throws {
        let img = CIImage(color: CIColor(red: 0.6, green: 0.5, blue: 0.4)).cropped(to: Self.rect)
        let m = try ModelSubjectMasker().subjectMask(for: img)
        #expect(m == nil || m?.extent == Self.rect)
    }
}
