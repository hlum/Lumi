import CoreImage
import Foundation
import Testing
@testable import Lumi

struct LUTTests {
    static func cube(size: Int, header: String = "", transform: (Float, Float, Float) -> (Float, Float, Float) = { ($0, $1, $2) }) -> String {
        var s = "# test\nTITLE \"t\"\n\(header)LUT_3D_SIZE \(size)\n"
        let d = Float(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let o = transform(Float(r) / d, Float(g) / d, Float(b) / d)
            s += "\(o.0) \(o.1) \(o.2)\n"
        } } }
        return s
    }

    @Test func parsesIdentityCube() throws {
        let l = try LUT.parse(cube: Self.cube(size: 3))
        #expect(l.size == 3)
        #expect(l == LUT.identity(size: 3))
    }

    @Test func redIsFastestAxis() throws {
        let l = try LUT.parse(cube: Self.cube(size: 2))
        #expect(Array(l.rgb[3..<6]) == [1, 0, 0])      // second entry: red=1
        #expect(Array(l.rgb[6..<9]) == [0, 1, 0])
    }

    @Test func missingSizeIsRejected() {
        #expect(throws: LUT.ParseError.missingSize) { try LUT.parse(cube: "0 0 0\n1 1 1\n") }
    }

    @Test func badSizesAreRejected() {
        #expect(throws: LUT.ParseError.badSize) { try LUT.parse(cube: "LUT_3D_SIZE 1\n") }
        #expect(throws: LUT.ParseError.badSize) { try LUT.parse(cube: "LUT_3D_SIZE abc\n") }
        #expect(throws: LUT.ParseError.badSize) { try LUT.parse(cube: "LUT_1D_SIZE 16\n") }
    }

    @Test func wrongEntryCountIsRejected() {
        #expect(throws: LUT.ParseError.badCount(expected: 8, got: 2)) { try LUT.parse(cube: "LUT_3D_SIZE 2\n0 0 0\n1 1 1\n") }
    }

    @Test func malformedLineReportsLineNumber() {
        #expect(throws: LUT.ParseError.badLine(2)) { try LUT.parse(cube: "LUT_3D_SIZE 2\n0 0\n") }
        #expect(throws: LUT.ParseError.badLine(2)) { try LUT.parse(cube: "LUT_3D_SIZE 2\n0 0 x\n") }
    }

    @Test func domainIsNormalized() throws {
        let c = Self.cube(size: 2, header: "DOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n") { ($0 * 2, $1 * 2, $2 * 2) }
        #expect(try LUT.parse(cube: c) == LUT.identity(size: 2))
    }

    @Test func emptyAndCommentOnlyInput() {
        #expect(throws: LUT.ParseError.missingSize) { try LUT.parse(cube: "") }
        #expect(throws: LUT.ParseError.missingSize) { try LUT.parse(cube: "# only a comment\n\n") }
    }

    @Test func sampleAtGridPointsAndBetween() {
        let l = LUT.identity(size: 5)
        let a = l.sample(0.25, 0.5, 0.75)
        #expect(abs(a.0 - 0.25) < 1e-6 && abs(a.1 - 0.5) < 1e-6 && abs(a.2 - 0.75) < 1e-6)
        let b = l.sample(0.13, 0.61, 0.99)           // between grid points: identity stays identity
        #expect(abs(b.0 - 0.13) < 1e-5 && abs(b.1 - 0.61) < 1e-5 && abs(b.2 - 0.99) < 1e-5)
        let c = l.sample(-3, 9, 1)                    // clamps
        #expect(c.0 == 0 && c.1 == 1 && c.2 == 1)
    }

    @Test func cubeDataSizeMatches() { #expect(LUT.identity(size: 4).cubeData.count == 4 * 4 * 4 * 4 * MemoryLayout<Float>.size) }

    @Test func identityLUTLeavesPixelsAlone() {
        let img = RendererTests.solid(0.4)
        let out = LUT.identity(size: 8).apply(to: img)
        #expect(abs(Int(RendererTests.pixel(out)[0]) - Int(RendererTests.pixel(img)[0])) <= 2)
    }

    @Test func invertLUTInverts() throws {
        let inv = try LUT.parse(cube: Self.cube(size: 8) { (1 - $0, 1 - $1, 1 - $2) })
        let out = RendererTests.pixel(inv.apply(to: RendererTests.solid(0.2)))
        #expect(abs(Int(out[0]) - Int((0.8 * 255).rounded())) <= 6)
    }

    @Test func intensityBlendsBetweenOriginalAndFull() throws {
        let inv = try LUT.parse(cube: Self.cube(size: 8) { (1 - $0, 1 - $1, 1 - $2) })
        let img = RendererTests.solid(0.2)
        let none = RendererTests.pixel(inv.apply(to: img, intensity: 0))[0]
        let half = RendererTests.pixel(inv.apply(to: img, intensity: 0.5))[0]
        let full = RendererTests.pixel(inv.apply(to: img, intensity: 1))[0]
        #expect(none < half && half < full)
        #expect(inv.apply(to: img, intensity: 0).extent == img.extent && inv.apply(to: img, intensity: 0.5).extent == img.extent)
        #expect(inv.apply(to: img, intensity: 7).extent == img.extent)   // clamps
    }
}
