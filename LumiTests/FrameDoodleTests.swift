import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FrameDoodleTests {
    static func photo(_ w: CGFloat = 200, _ h: CGFloat = 100) -> CIImage { CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.9)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) }
    static func cfg(_ s: FrameConfig.Style, pad: Double = 0.1, color: RGBA = .white) -> FrameConfig { FrameConfig(style: s, padding: pad, color: color) }

    // MARK: frames
    @Test func zeroPaddingIsIdentity() {
        #expect(FrameConfig(padding: 0).isIdentity)
        #expect(FrameOps.apply(FrameConfig(padding: 0), to: Self.photo()).extent == Self.photo().extent)
    }

    @Test func outerFrameAddsSpaceAroundThePhoto() {
        let o = FrameOps.apply(Self.cfg(.outer), to: Self.photo())
        #expect(o.extent == CGRect(x: 0, y: 0, width: 220, height: 120))           // pad = 10% of the short side = 10
        #expect(FrameOps.outputSize(Self.cfg(.outer), for: CGSize(width: 200, height: 100)) == CGSize(width: 220, height: 120))
        #expect(GeometryTests.rgb(o, x: 2, y: 2).prefix(3).allSatisfy { $0 > 240 })        // white margin
        #expect(GeometryTests.rgb(o, x: 110, y: 60)[2] > 200 && GeometryTests.rgb(o, x: 110, y: 60)[0] < 80)   // photo untouched
    }

    @Test func posterHasAWiderBottomMargin() {
        let o = FrameOps.apply(Self.cfg(.poster), to: Self.photo())
        #expect(o.extent.height == 100 + 10 + 35 && o.extent.width == 220)
        #expect(GeometryTests.rgb(o, x: 110, y: 20)[0] > 240)                              // the bottom margin (low y) is white
        #expect(FrameOps.outputSize(Self.cfg(.poster), for: CGSize(width: 200, height: 100)) == CGSize(width: 220, height: 145))
    }

    @Test func innerFrameKeepsSizeAndDrawsTheBorderOverThePhoto() {
        let o = FrameOps.apply(Self.cfg(.inner), to: Self.photo())
        #expect(o.extent == Self.photo().extent)
        #expect(GeometryTests.rgb(o, x: 3, y: 50)[0] > 240)                                // border on the left edge
        #expect(GeometryTests.rgb(o, x: 100, y: 50)[0] < 80)                               // center still the photo
    }

    @Test func simpleFrameIsAThinInsetLine() {
        let o = FrameOps.apply(Self.cfg(.simple, pad: 0.2), to: Self.photo())
        #expect(o.extent == Self.photo().extent)
        #expect(GeometryTests.rgb(o, x: 2, y: 50)[0] < 80)                                 // outside the line: photo
        #expect(GeometryTests.rgb(o, x: 100, y: 50)[0] < 80)
        #expect((15...30).contains { GeometryTests.rgb(o, x: $0, y: 50)[0] > 200 })         // the line itself
    }

    @Test func cornerRadiusRoundsTheInnerEdgeAndPaddingIsClamped() {
        var c = Self.cfg(.inner); c.cornerRadius = 0.3
        #expect(GeometryTests.rgb(FrameOps.apply(c, to: Self.photo()), x: 0, y: 0)[0] < 80)    // the very corner is cut away by the radius
        #expect(FrameOps.outputSize(FrameConfig(style: .outer, padding: 9), for: CGSize(width: 100, height: 100)) == CGSize(width: 150, height: 150))   // 25% cap
    }

    @Test func frameIsADocumentOperation() throws {
        var d = EditDocument(); d.frame = Self.cfg(.outer, color: RGBA(r: 1, g: 0.95, b: 0.8, a: 1))
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).frame == d.frame)
        #expect(Renderer.render(Self.photo(), document: d).extent.width > 200)
        d.frame = FrameConfig(padding: 0); #expect(d.operations.isEmpty)
    }

    // MARK: doodle
    @Test func straightStrokesSnapToALineAndCurvesDoNot() {
        let straight = (0...20).map { CGPoint(x: Double($0) / 20, y: 0.5 + (($0 % 2 == 0) ? 0.003 : -0.003)) }
        #expect(Doodle.snappedToLine(straight).count == 2)
        let curve = (0...20).map { CGPoint(x: Double($0) / 20, y: 0.5 + 0.2 * sin(Double($0) / 3)) }
        #expect(Doodle.snappedToLine(curve).count == 21)
        #expect(Doodle.snappedToLine([CGPoint(x: 0.1, y: 0.1)]).count == 1 && Doodle.snappedToLine([]).isEmpty)
        #expect(Doodle.snappedToLine([CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.1, y: 0.1)]).count == 3)    // a dot stays a dot
    }

    @Test(arguments: DoodleStroke.Brush.allCases)
    func everyBrushDrawsSomethingAndKeepsTheExtent(brush: DoodleStroke.Brush) {
        let s = DoodleStroke(brush: brush, points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.9, y: 0.5)], color: RGBA(r: 1, g: 0, b: 0, a: 1), size: 0.03)
        let base = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let out = Doodle.render([s], over: base)
        #expect(out.extent == base.extent)
        var buf = [UInt8](repeating: 0, count: 4 * 200 * 100)
        GeometryTests.ctx.render(out, toBitmap: &buf, rowBytes: 800, bounds: out.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(buf.enumerated().contains { $0.offset % 4 == 1 && $0.element < 200 }, "\(brush) left no mark")      // green channel dropped somewhere: red ink on white
    }

    @Test func strokeLandsWhereTheNormalizedPointsSayYDown() {
        let s = DoodleStroke(brush: .solid, points: [CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.5, y: 0.2)], color: RGBA(r: 1, g: 0, b: 0, a: 1), size: 0.1)
        let out = Doodle.render([s], over: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
        #expect(GeometryTests.rgb(out, x: 50, y: 80)[1] < 100)           // y-down 0.2 => CI y = 80
        #expect(GeometryTests.rgb(out, x: 50, y: 20)[1] > 240)
    }

    @Test func markerMultipliesSoTextUnderneathShowsThrough() {
        let base = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let s = DoodleStroke(brush: .marker, points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)], color: RGBA(r: 1, g: 1, b: 0, a: 1), size: 0.05, opacity: 1)
        let out = Doodle.render([s], over: base)
        let p = GeometryTests.rgb(out, x: 50, y: 50), q = GeometryTests.rgb(base, x: 50, y: 50)
        #expect(p[2] < q[2] && abs(Int(p[0]) - Int(q[0])) < 40)          // yellow multiply keeps red/green, drops blue
    }

    @Test func opacityLightensTheStroke() {
        let base = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        func g(_ o: Double) -> Int { Int(GeometryTests.rgb(Doodle.render([DoodleStroke(points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)], color: RGBA(r: 1, g: 0, b: 0, a: 1), size: 0.1, opacity: o)], over: base), x: 50, y: 50)[1]) }
        #expect(g(0.3) > g(1))
    }

    @Test func emptyAndEmptyPointStrokesAreIgnored() {
        let base = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(Doodle.render([], over: base).extent == base.extent)
        #expect(GeometryTests.rgb(Doodle.render([DoodleStroke(points: [])], over: base), x: 25, y: 25)[1] > 240)
    }

    @Test func doodleIsADocumentOperationThatRendersAndUndoes() throws {
        var d = EditDocument()
        d.doodle = [DoodleStroke(brush: .neon, points: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)])]
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).doodle == d.doodle)
        d.doodle = []; #expect(d.operations.isEmpty)
    }
}
