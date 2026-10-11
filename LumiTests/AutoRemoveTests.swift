import CoreImage
import Foundation
import Testing
@testable import Lumi

struct AutoRemoveTests {
    static let ext = CGRect(x: 0, y: 0, width: 200, height: 200)
    static func person(_ b: CGRect) -> PersonInstance { PersonInstance(mask: MosaicOps.mask(rects: [b], extent: ext), box: b) }
    static let main = person(CGRect(x: 0.35, y: 0.1, width: 0.3, height: 0.8))              // big and central
    static let left = person(CGRect(x: 0.02, y: 0.3, width: 0.12, height: 0.3))             // small passer-by
    static let right = person(CGRect(x: 0.85, y: 0.2, width: 0.1, height: 0.25))

    @Test func theBigCentralPersonIsTheMainSubject() {
        #expect(AutoRemove.mainSubject([Self.left, Self.main, Self.right]) == Self.main)
        #expect(AutoRemove.mainSubject([]) == nil)
    }

    @Test func aBigPersonAtTheEdgeLosesToAnAlmostAsBigCentralOne() {
        let edge = Self.person(CGRect(x: 0.78, y: 0.1, width: 0.22, height: 0.8)), centre = Self.person(CGRect(x: 0.3, y: 0.15, width: 0.22, height: 0.7))
        #expect(AutoRemove.mainSubject([edge, centre]) == centre)
    }

    @Test func passersByAreEveryoneExceptTheMainSubject() {
        let by = AutoRemove.passersBy([Self.left, Self.main, Self.right])
        #expect(by.count == 2 && !by.contains(Self.main))
        #expect(AutoRemove.passersBy([Self.main]).isEmpty && AutoRemove.passersBy([]).isEmpty)
    }

    @Test func combinedMaskCoversThePassersByAndNotTheMainSubject() throws {
        let m = try #require(AutoRemove.combinedMask(AutoRemove.passersBy([Self.left, Self.main, Self.right]), extent: Self.ext))
        #expect(GeometryTests.rgb(m, x: 16, y: 90)[0] > 200)                                   // left passer-by
        #expect(GeometryTests.rgb(m, x: 180, y: 50)[0] > 200)                                  // right passer-by
        #expect(GeometryTests.rgb(m, x: 100, y: 100)[0] < 30)                                  // main subject untouched
        #expect(AutoRemove.combinedMask([], extent: Self.ext) == nil)
    }

    @Test func textMaskCoversEachBoxWithAMargin() throws {
        let box = CGRect(x: 0.4, y: 0.5, width: 0.2, height: 0.05)
        let m = try #require(AutoRemove.textMask([box], extent: Self.ext))
        #expect(GeometryTests.rgb(m, x: 100, y: 105)[0] > 200)                                 // inside the line
        #expect(GeometryTests.rgb(m, x: 78, y: 105)[0] > 200)                                  // inside the margin (box starts at x=80)
        #expect(GeometryTests.rgb(m, x: 20, y: 20)[0] < 20 && AutoRemove.textMask([], extent: Self.ext) == nil)
    }

    @Test func maskBoundsAreTightAndNormalized() throws {
        let b = try #require(MaskBounds.normalizedBounds(of: MosaicOps.mask(rects: [CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25)], extent: Self.ext)))
        #expect(abs(b.minX - 0.25) < 0.03 && abs(b.minY - 0.5) < 0.03 && abs(b.width - 0.5) < 0.04 && abs(b.height - 0.25) < 0.04)
        #expect(MaskBounds.normalizedBounds(of: CIImage(color: .black).cropped(to: Self.ext)) == nil)
    }

    @MainActor @Test func theRemoverTakesAnAutoSelectionAsIfPaintedAndUndoRestoresIt() throws {
        let r = RemoverModel(imageSize: CGSize(width: 200, height: 200))
        let m = try #require(AutoRemove.combinedMask(AutoRemove.passersBy([Self.left, Self.main]), extent: Self.ext))
        r.select(m, extent: Self.ext)
        #expect(r.hasSelection)
        // the left passer-by is around x 0.02-0.14 of the width, 0.3-0.6 up from the bottom: mask rows are top-first
        let w = r.mask.width, h = r.mask.height
        #expect(r.mask[Int(0.08 * Double(w)), Int((1 - 0.45) * Double(h))] == 255)
        #expect(r.mask[w / 2, h / 2] == 0)                                                    // the main subject stays clear
        r.undoStroke(); #expect(!r.hasSelection)
    }

    @Test func visionPeopleFinderReturnsWellFormedBoxes() throws {
        // Vision's person model can "see" someone in a flat picture, so only the shape of the answer is checked
        let people = try VisionPeopleFinder().people(in: CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200)))
        for p in people { #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(p.box) && p.area > 0) }
    }
}
