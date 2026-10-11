import Foundation
import Testing
@testable import Lumi

struct SmoothingTests {
    /// Deterministic pseudo-noise so the test never flakes.
    static func noise(_ i: Int) -> Double { Double((i * 7919) % 200) / 100 - 1 }

    @Test func firstSampleIsPassedThrough() {
        var f = OneEuroFilter()
        #expect(f.filter(5, at: 0) == 5)
    }

    @Test func steadySignalConverges() {
        var f = OneEuroFilter()
        var out = 0.0
        for i in 0..<200 { out = f.filter(3, at: Double(i) / 60) }
        #expect(abs(out - 3) < 1e-6)
    }

    @Test func reducesJitterOnNoisyStillTrack() {
        var f = OneEuroFilter(minCutoff: 1, beta: 0)
        func variance(_ v: [Double]) -> Double { let m = v.reduce(0, +) / Double(v.count); return v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(v.count) }
        let raw = (0..<300).map { 10 + Self.noise($0) * 0.5 }
        let smooth = raw.enumerated().map { f.filter($1, at: Double($0) / 60) }
        #expect(variance(Array(smooth.dropFirst(30))) < variance(Array(raw.dropFirst(30))) / 4)
    }

    @Test func followsFastMovementWithBeta() {
        var slow = OneEuroFilter(minCutoff: 0.5, beta: 0), fast = OneEuroFilter(minCutoff: 0.5, beta: 5)
        var a = 0.0, b = 0.0
        for i in 0..<60 { let v = Double(i); a = slow.filter(v, at: Double(i) / 60); b = fast.filter(v, at: Double(i) / 60) }
        #expect(abs(59 - b) < abs(59 - a))      // speed-adaptive cutoff lags less
    }

    @Test func nonAdvancingTimeDoesNotProduceNaN() {
        var f = OneEuroFilter()
        _ = f.filter(1, at: 1)
        let v = f.filter(2, at: 1)
        #expect(v.isFinite)
        #expect(f.filter(3, at: 0.5).isFinite)
    }

    @Test func resetForgetsHistory() {
        var f = OneEuroFilter()
        _ = f.filter(100, at: 0); _ = f.filter(100, at: 1)
        f.reset()
        #expect(f.filter(0, at: 2) == 0)
    }

    @Test func pointSmootherSmoothsBothAxes() {
        var s = PointSmoother(minCutoff: 1, beta: 0)
        var last = CGPoint.zero
        for i in 0..<120 { last = s.filter(CGPoint(x: 5 + Self.noise(i), y: 9 - Self.noise(i)), at: Double(i) / 60) }
        #expect(abs(last.x - 5) < 0.5 && abs(last.y - 9) < 0.5)
    }
}
