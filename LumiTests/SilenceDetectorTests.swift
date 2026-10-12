import Foundation
import Testing
@testable import Lumi

struct SilenceDetectorTests {
    let sr = 1000.0
    /// Seconds of tone (amplitude .5) or silence, in order.
    func signal(_ parts: [(Double, Bool)]) -> [Float] {
        parts.flatMap { secs, loud in (0..<Int(secs * sr)).map { i in loud ? 0.5 * sin(Float(i) * 0.3) : 0 } }
    }

    @Test func findsSilenceInTheMiddle() {
        let r = SilenceDetector.silentRanges(signal([(1, true), (2, false), (1, true)]), sampleRate: sr)
        #expect(r.count == 1 && abs(r[0].lowerBound - 1) < 0.05 && abs(r[0].upperBound - 3) < 0.05)
    }

    @Test func shortPausesAreKeptAndEdgesCount() {
        #expect(SilenceDetector.silentRanges(signal([(1, true), (0.3, false), (1, true)]), sampleRate: sr).isEmpty)
        let r = SilenceDetector.silentRanges(signal([(1, false), (1, true), (1, false)]), sampleRate: sr)
        #expect(r.count == 2 && r[0].lowerBound == 0 && abs(r[1].upperBound - 3) < 0.05)
        #expect(SilenceDetector.silentRanges([], sampleRate: sr).isEmpty)
        #expect(SilenceDetector.silentRanges(signal([(2, true)]), sampleRate: sr).isEmpty)
    }

    @Test func keepRangesLeaveRoomAroundCuts() {
        let keep = SilenceDetector.keepRanges(duration: 4, silent: [1.0..<3.0], padding: 0.1)
        #expect(keep.count == 2 && abs(keep[0].upperBound - 1.1) < 1e-9 && abs(keep[1].lowerBound - 2.9) < 1e-9 && keep[1].upperBound == 4)
        #expect(SilenceDetector.keepRanges(duration: 4, silent: [], padding: 0.1) == [0..<4])
        #expect(SilenceDetector.keepRanges(duration: 4, silent: [1.0..<1.1], padding: 0.1) == [0..<4])     // too short to cut
    }

    @Test func beatsFollowLoudBursts() {
        let s = signal([(0.5, false), (0.1, true), (0.4, false), (0.1, true), (0.9, false)])
        let b = SilenceDetector.beats(s, sampleRate: sr)
        #expect(b.count == 2 && abs(b[0] - 0.5) < 0.05 && abs(b[1] - 1.0) < 0.05)
        #expect(SilenceDetector.beats([], sampleRate: sr).isEmpty)
    }
}
