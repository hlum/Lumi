import Foundation
import Testing
@testable import Lumi

struct AudioTrackTests {
    func clip(_ len: Double = 10, start: Double = 2) -> AudioClip { AudioClip(source: .file(URL(filePath: "/a.m4a")), duration: len, start: start) }

    @Test func gainIsZeroOutsideAndRampsOnFades() {
        var c = clip(); c.fadeIn = 2; c.fadeOut = 2; c.volume = 1
        #expect(c.gain(at: 1.9) == 0 && c.gain(at: 12) == 0)
        #expect(abs(c.gain(at: 3) - 0.5) < 1e-9 && c.gain(at: 7) == 1 && abs(c.gain(at: 11) - 0.5) < 1e-9)
        c.volume = 5; #expect(c.gain(at: 7) == 2)
        c.volume = -1; #expect(c.gain(at: 7) == 0)
    }

    @Test func fadesNeverOverlap() {
        var c = clip(4); c.setFades(in: 3, out: 3)
        #expect(c.fadeIn + c.fadeOut <= 4 + 1e-9 && c.fadeIn == c.fadeOut)
        c.setFades(in: -1, out: 0); #expect(c.fadeIn == 0 && c.fadeOut == 0)
    }

    @Test func trimShortensAndKeepsFadesInside() {
        var c = clip(10); c.fadeIn = 3; c.fadeOut = 3
        c.trim(in: 2, out: 6, sourceDuration: 10)
        #expect(c.length == 4 && c.end == 6 && c.fadeIn + c.fadeOut <= 4)
        c.trim(in: 20, out: 3, sourceDuration: 10); #expect(c.length == 0)
    }

    @Test func splitMakesTwoContiguousPieces() {
        let c = clip(10, start: 2)
        let (a, b) = c.split(at: 5)!
        #expect(a.length == 3 && b.length == 7 && a.end == b.start && b.trimIn == a.trimOut && a.id != b.id)
        #expect(c.split(at: 2) == nil && c.split(at: 12) == nil)
    }

    @Test func tracksMixAndDuck() {
        var t = AudioTracks()
        let music = clip(10, start: 0)
        var voice = AudioClip(source: .voiceOver(URL(filePath: "/v.m4a")), duration: 2, start: 4)
        voice.volume = 1
        t.add(music); t.add(voice)
        #expect(t.duration == 10 && t.gain(at: 5) == 2)
        #expect(t.duckedGain(of: music, at: 5) == 0.3 && t.duckedGain(of: music, at: 8) == 1)
        t.remove(voice.id); #expect(t.clips.count == 1)
    }
}
