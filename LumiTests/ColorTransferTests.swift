import Foundation
import Testing
@testable import Lumi

struct ColorTransferTests {
    @Test func labRoundTrips() {
        for (r, g, b) in [(0.0, 0.0, 0.0), (1.0, 1.0, 1.0), (0.2, 0.5, 0.8), (0.9, 0.1, 0.3)] {
            let l = ColorTransfer.lab(r, g, b)
            let o = ColorTransfer.rgb(fromLab: l[0], l[1], l[2])
            #expect(abs(o.0 - r) < 1e-4 && abs(o.1 - g) < 1e-4 && abs(o.2 - b) < 1e-4)
        }
    }

    @Test func labKnownValues() {
        let white = ColorTransfer.lab(1, 1, 1), black = ColorTransfer.lab(0, 0, 0)
        #expect(abs(white[0] - 100) < 0.1 && abs(white[1]) < 0.1 && abs(white[2]) < 0.1)
        #expect(abs(black[0]) < 0.1)
    }

    @Test func statsOfEmptyAreZero() { #expect(ColorTransfer.stats(ofRGB: []).std == [0, 0, 0]) }

    @Test func statsOfFlatImageHaveNoSpread() {
        let s = ColorTransfer.stats(ofRGB: Array(repeating: Float(0.5), count: 30))
        #expect(s.std.allSatisfy { $0 < 1e-6 } && abs(s.mean[0] - ColorTransfer.lab(0.5, 0.5, 0.5)[0]) < 1e-6)
    }

    @Test func transferToSelfIsIdentity() {
        let px: [Float] = [0.1, 0.2, 0.3, 0.8, 0.7, 0.2, 0.5, 0.5, 0.9, 0.3, 0.6, 0.1]
        let s = ColorTransfer.stats(ofRGB: px)
        let l = ColorTransfer.lut(target: s, reference: s, size: 9)
        for c in stride(from: 0, to: px.count, by: 3) {
            let o = l.sample(px[c], px[c + 1], px[c + 2])
            #expect(abs(o.0 - px[c]) < 0.02 && abs(o.1 - px[c + 1]) < 0.02 && abs(o.2 - px[c + 2]) < 0.02)
        }
    }

    @Test func graySourceWarmsTowardWarmReference() {
        let gray = ColorTransfer.stats(ofRGB: [0.3, 0.3, 0.3, 0.7, 0.7, 0.7])
        let warm = ColorTransfer.stats(ofRGB: [0.8, 0.5, 0.3, 0.95, 0.7, 0.45])
        let o = ColorTransfer.lut(target: gray, reference: warm, size: 9).sample(0.5, 0.5, 0.5)
        #expect(o.0 > o.2)       // red over blue: the grade transferred
    }

    @Test func zeroStrengthIsIdentity() {
        let a = ColorTransfer.stats(ofRGB: [0.1, 0.1, 0.1, 0.9, 0.9, 0.9]), b = ColorTransfer.stats(ofRGB: [0.8, 0.4, 0.2, 0.9, 0.6, 0.3])
        let l = ColorTransfer.lut(target: a, reference: b, size: 5, strength: 0)
        #expect(l == LUT.identity(size: 5))
    }

    @Test func outputStaysInGamut() {
        let a = ColorTransfer.stats(ofRGB: [0.5, 0.5, 0.5, 0.52, 0.5, 0.5]), b = ColorTransfer.stats(ofRGB: [0, 0, 0, 1, 1, 1])
        let l = ColorTransfer.lut(target: a, reference: b, size: 5)
        #expect(l.rgb.allSatisfy { $0 >= 0 && $0 <= 1 && $0.isFinite })
    }
}
