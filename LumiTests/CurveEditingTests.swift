import CoreImage
import CoreGraphics
import Testing
@testable import Lumi

struct CurveEditingTests {
    let line = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]
    let three = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)]

    @Test func nearestFindsTheClosePointWithinTheRadius() {
        #expect(CurveEditing.nearest(three, to: CGPoint(x: 0.52, y: 0.49), within: 0.05) == 1)
        #expect(CurveEditing.nearest(three, to: CGPoint(x: 0.3, y: 0.9), within: 0.05) == nil)
        #expect(CurveEditing.nearest(three, to: CGPoint(x: 0.97, y: 0.99), within: 0.1) == 2)
    }

    @Test func endPointsOnlyMoveUpAndDown() {
        let a = CurveEditing.move(three, index: 0, to: CGPoint(x: 0.4, y: 0.3))
        #expect(a[0] == CGPoint(x: 0, y: 0.3))
        let b = CurveEditing.move(three, index: 2, to: CGPoint(x: 0.2, y: 5))
        #expect(b[2] == CGPoint(x: 1, y: 1))
    }

    @Test func innerPointsStayBetweenTheirNeighbours() {
        let m = CurveEditing.move(three, index: 1, to: CGPoint(x: 3, y: -2))
        #expect(m[1].x <= 1 - CurveEditing.minGap + 1e-9 && m[1].y == 0)
        let l = CurveEditing.move(three, index: 1, to: CGPoint(x: -3, y: 0.5))
        #expect(l[1].x >= CurveEditing.minGap - 1e-9)
        #expect(CurveEditing.move(three, index: 9, to: .zero) == three)
    }

    @Test func insertKeepsOrderAndRefusesCrowdingAndEnds() {
        let r = CurveEditing.insert(line, at: CGPoint(x: 0.3, y: 0.2))!
        #expect(r.points.map(\.x) == [0, 0.3, 1] && r.index == 1)
        #expect(CurveEditing.insert(r.points, at: CGPoint(x: 0.31, y: 0.5)) == nil)             // too close to 0.3
        #expect(CurveEditing.insert(line, at: CGPoint(x: 0, y: 0.5)) == nil && CurveEditing.insert(line, at: CGPoint(x: 1, y: 0.5)) == nil)
        var full = line
        for i in 1..<(CurveEditing.maxPoints - 1) { full = CurveEditing.insert(full, at: CGPoint(x: Double(i) * 0.08, y: 0.5))!.points }
        #expect(full.count == CurveEditing.maxPoints)
        #expect(CurveEditing.insert(full, at: CGPoint(x: 0.95, y: 0.5)) == nil)             // no room left
    }

    @Test func removeKeepsTheEnds() {
        #expect(CurveEditing.remove(three, index: 1) == line)
        #expect(CurveEditing.remove(three, index: 0) == three && CurveEditing.remove(three, index: 2) == three)
    }

    @Test func colourMatchMovesTheLookTowardTheReference() {
        let ref = CIImage(color: CIColor(red: 0.9, green: 0.6, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let m = ColorMatch.from(reference: ref, name: "warm")!
        #expect(!m.isIdentity && m.mean.count == 3)
        var strong = m; strong.strength = 1
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let out = strong.apply(to: grey)
        var px = [UInt8](repeating: 0, count: 4)
        CIContext().render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 10, y: 10, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(px[0] > px[2] + 20)                                                     // warmer than the grey it started as
        var off = m; off.strength = 0
        #expect(off.isIdentity && off.apply(to: grey) == grey)
        var d = EditDocument(); d.colorMatch = m
        #expect(d.operations.count == 1 && d.operations[0].kind == .match)
        d.colorMatch = ColorMatch(); #expect(d.operations.isEmpty)
    }
}
