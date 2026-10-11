import CoreImage
import Foundation
import Testing
@testable import Lumi

struct AutoMosaicTests {
    static func face(_ r: CGRect) -> FaceInfo { FaceInfo(box: r, landmarks: [:]) }

    @Test func coversEveryDetectedFaceWithPadding() {
        let f1 = CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.2), f2 = CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.2)
        let r = AutoMosaic.faceRegions([Self.face(f1), Self.face(f2)])
        #expect(r.count == 2)
        #expect(r[0].contains(f1) && r[1].contains(f2))
    }

    @Test func paddingIsClampedToImage() {
        let r = AutoMosaic.faceRegions([Self.face(CGRect(x: 0, y: 0, width: 0.3, height: 0.3))])[0]
        #expect(r.minX >= 0 && r.minY >= 0 && r.maxX <= 1 && r.maxY <= 1)
    }

    @Test func protectedSubjectFaceIsSkipped() {
        let mine = CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.2), other = CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.2)
        let r = AutoMosaic.faceRegions([Self.face(mine), Self.face(other)], skipping: [CGRect(x: 0, y: 0.3, width: 0.5, height: 0.5)])
        #expect(r.count == 1 && r[0].contains(other))
    }

    @Test func noFacesNoRegions() { #expect(AutoMosaic.faceRegions([]).isEmpty) }

    @Test func chatNamesAndAvatarsAreCovered() {
        // portrait screenshot: aspect (w/h) 0.46. A short name at the left, a long message in the middle.
        let name = CGRect(x: 0.2, y: 0.80, width: 0.15, height: 0.015)
        let message = CGRect(x: 0.2, y: 0.74, width: 0.60, height: 0.02)      // too wide: a message, not a name
        let r = AutoMosaic.chatRegions(textBoxes: [name, message], imageAspect: 0.46)
        #expect(r.contains { $0.contains(name) })
        #expect(!r.contains { $0.contains(message) })
        #expect(r.count == 2)                                                  // name + avatar square
        #expect(r.contains { $0.maxX <= name.minX })                          // avatar sits left of the name
    }

    @Test func textOnTheRightIsIgnored() {
        #expect(AutoMosaic.chatRegions(textBoxes: [CGRect(x: 0.7, y: 0.5, width: 0.1, height: 0.02)], imageAspect: 0.5).isEmpty)
    }

    @Test func avatarOmittedWhenNoRoomOnTheLeft() {
        let r = AutoMosaic.chatRegions(textBoxes: [CGRect(x: 0.01, y: 0.5, width: 0.1, height: 0.02)], imageAspect: 0.5)
        #expect(r.count == 1)
    }

    @Test func mergeJoinsOverlapsAndKeepsDisjoint() {
        let m = AutoMosaic.merge([CGRect(x: 0, y: 0, width: 0.3, height: 0.3), CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), CGRect(x: 0.8, y: 0.8, width: 0.1, height: 0.1)])
        #expect(m.count == 2)
        #expect(m.contains(CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        #expect(AutoMosaic.merge([]).isEmpty)
        #expect(AutoMosaic.merge([.null, .zero]).isEmpty)
    }

    @Test func mosaicChangesOnlyMaskedArea() {
        // checkerboard so pixelation visibly changes pixels
        let checker = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 2, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let mask = MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], extent: checker.extent)
        let out = MosaicOps.apply(.pixel, to: checker, mask: mask, block: 16)
        #expect(out.extent == checker.extent)
        func differs(_ x: Int) -> Bool { GeometryTests.rgb(out, x: x, y: 10) != GeometryTests.rgb(checker, x: x, y: 10) }
        let leftChanged = (0..<30).contains { differs($0) }
        let rightSame = (34..<64).allSatisfy { !differs($0) }
        #expect(leftChanged && rightSame)
    }

    @Test func blurStyleKeepsExtent() {
        let img = RendererTests.solid(0.5, size: 32)
        let out = MosaicOps.apply(.blur, to: img, mask: MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 1, height: 1)], extent: img.extent), block: 4)
        #expect(out.extent == img.extent)
    }
}
