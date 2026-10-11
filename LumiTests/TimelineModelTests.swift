import Foundation
import Testing
@testable import Lumi

struct TimelineModelTests {
    static func clip(_ name: String = "a", _ d: Double = 10, speed: Double = 1) -> TimelineClip {
        var c = TimelineClip(source: .video(name), sourceDuration: d); c.speed = speed; return c
    }
    static func timeline(_ clips: [TimelineClip]) -> Timeline { var t = Timeline(); clips.forEach { t.append($0) }; return t }

    @Test func durationSumsClipsAndRespectsSpeed() {
        let t = Self.timeline([Self.clip("a", 10), Self.clip("b", 10, speed: 2)])
        #expect(t.duration == 15)                                  // 10 + 10/2
        #expect(Timeline().duration == 0 && Timeline().isEmpty)
    }

    @Test func speedIsClampedInDuration() {
        #expect(Self.clip("a", 10, speed: 100).duration == 10.0 / 8)
        #expect(Self.clip("a", 10, speed: 0).duration == 100)
    }

    @Test func locateFindsTheClipUnderATime() {
        let t = Self.timeline([Self.clip("a", 4), Self.clip("b", 6)])
        #expect(t.locate(0)?.index == 0 && t.locate(3.99)?.index == 0)
        #expect(t.locate(4)?.index == 1 && abs(t.locate(5)!.offset - 1) < 1e-9)
        #expect(t.locate(10) == nil && t.locate(-1) == nil)
    }

    @Test func startOfClipIsTheSumOfEarlierClips() {
        let a = Self.clip("a", 4), b = Self.clip("b", 6), t = Self.timeline([a, b])
        #expect(t.start(of: a.id) == 0 && t.start(of: b.id) == 4 && t.start(of: UUID()) == nil)
    }

    @Test func removeMoveDuplicate() throws {
        let a = Self.clip("a"), b = Self.clip("b"), c = Self.clip("c")
        var t = Self.timeline([a, b, c])
        try t.move(a.id, to: 2); #expect(t.clips.map(\.id) == [b.id, c.id, a.id])
        try t.move(a.id, to: 99); #expect(t.clips.last?.id == a.id)
        try t.duplicate(b.id)
        #expect(t.clips.count == 4 && t.clips[1].id != b.id && t.clips[1].source == b.source)
        try t.remove(b.id); #expect(t.clips.count == 3)
        #expect(throws: Timeline.EditError.noSuchClip) { try t.remove(UUID()) }
        #expect(throws: Timeline.EditError.noSuchClip) { try t.move(UUID(), to: 0) }
        #expect(throws: Timeline.EditError.noSuchClip) { try t.duplicate(UUID()) }
    }

    @Test func insertClampsTheIndex() {
        var t = Self.timeline([Self.clip("a")])
        t.insert(Self.clip("b"), at: -5); t.insert(Self.clip("c"), at: 99)
        #expect(t.clips.count == 3 && t.clips.first?.source == .video("b") && t.clips.last?.source == .video("c"))
    }

    @Test func trimSetsTheSourceRangeAndShortensTheTimeline() throws {
        let a = Self.clip("a", 10); var t = Self.timeline([a])
        try t.trim(a.id, start: 2, duration: 5)
        #expect(t.clips[0].sourceStart == 2 && t.duration == 5)
        #expect(throws: Timeline.EditError.tooShort) { try t.trim(a.id, start: 0, duration: 0.01) }
        #expect(throws: Timeline.EditError.outOfRange) { try t.trim(a.id, start: -1, duration: 2) }
        #expect(throws: Timeline.EditError.outOfRange) { try t.trim(a.id, start: 0, duration: 0) }
    }

    @Test func splitMakesTwoClipsThatCoverTheOriginal() throws {
        let a = Self.clip("a", 10); var t = Self.timeline([a])
        let (f, s) = try t.split(at: 4)
        #expect(t.clips.count == 2 && t.clips[0].id == f && t.clips[1].id == s && f != s)
        #expect(t.clips[0].sourceStart == 0 && t.clips[0].sourceDuration == 4)
        #expect(t.clips[1].sourceStart == 4 && t.clips[1].sourceDuration == 6)
        #expect(t.duration == 10)                                                      // splitting never changes total length
    }

    @Test func splitAccountsForSpeedAndReversal() throws {
        var fast = Self.clip("a", 10, speed: 2); fast.sourceStart = 1
        var t = Self.timeline([fast])
        _ = try t.split(at: 1)                                  // 1 s of timeline = 2 s of source
        #expect(t.clips[0].sourceDuration == 2 && t.clips[1].sourceStart == 3 && t.duration == 5)
        var rev = Self.clip("r", 10); rev.isReversed = true
        var r = Self.timeline([rev])
        _ = try r.split(at: 3)                                  // reversed: the first 3 s come from the source tail
        #expect(r.clips[0].sourceStart == 7 && r.clips[0].sourceDuration == 3 && r.clips[1].sourceStart == 0 && r.clips[1].sourceDuration == 7)
    }

    @Test func splitRejectsOutOfRangeAndTinyPieces() {
        var t = Self.timeline([Self.clip("a", 10)])
        #expect(throws: Timeline.EditError.outOfRange) { try t.split(at: 10) }
        #expect(throws: Timeline.EditError.outOfRange) { try t.split(at: -1) }
        #expect(throws: Timeline.EditError.tooShort) { try t.split(at: 0.05) }
        #expect(throws: Timeline.EditError.tooShort) { try t.split(at: 9.95) }
        #expect(t.clips.count == 1)
    }

    @Test func splitInTheSecondClipTouchesOnlyThatClip() throws {
        let a = Self.clip("a", 4), b = Self.clip("b", 6); var t = Self.timeline([a, b])
        _ = try t.split(at: 7)
        #expect(t.clips.count == 3 && t.clips[0] == a && t.clips[1].sourceDuration == 3)
    }

    @Test func replaceKeepsPositionAndResetsTrim() throws {
        let a = Self.clip("a", 10), b = Self.clip("b", 5); var t = Self.timeline([a, b])
        try t.trim(a.id, start: 3, duration: 2)
        try t.replace(a.id, with: .photo("p"), duration: 3)
        #expect(t.clips[0].id == a.id && t.clips[0].isPhoto && t.clips[0].sourceStart == 0 && t.clips[0].sourceDuration == 3)
        #expect(throws: Timeline.EditError.tooShort) { try t.replace(a.id, with: .photo("q"), duration: 0) }
    }

    @Test func speedVolumeAndReverseAreClamped() throws {
        let a = Self.clip(); var t = Self.timeline([a])
        try t.setSpeed(a.id, 50); try t.setVolume(a.id, 3); try t.setReversed(a.id, true)
        #expect(t.clips[0].speed == 8 && t.clips[0].volume == 1 && t.clips[0].isReversed)
        try t.setSpeed(a.id, 0); try t.setVolume(a.id, -2)
        #expect(t.clips[0].speed == 0.1 && t.clips[0].volume == 0)
        #expect(throws: Timeline.EditError.noSuchClip) { try t.setSpeed(UUID(), 1) }
    }

    @Test func photosAreClipsWithADisplayTime() {
        let p = TimelineClip(source: .photo("p"), sourceDuration: TimelineClip.photoDefault)
        #expect(p.isPhoto && p.duration == 3)
    }

    @Test func undoWorksBecauseTheTimelineIsAValueType() throws {
        var stack = UndoStack(Timeline())
        var t = stack.current; t.append(Self.clip("a")); stack.commit(t)
        var t2 = stack.current; _ = try t2.split(at: 5); stack.commit(t2)
        #expect(stack.current.clips.count == 2)
        stack.undo(); #expect(stack.current.clips.count == 1)
        stack.undo(); #expect(stack.current.isEmpty)
    }

    @Test func draftRoundTripsThroughJSON() throws {
        var d = VideoDraft(); d.timeline.append(Self.clip("a")); d.export.fps = 60
        #expect(try JSONDecoder().decode(VideoDraft.self, from: JSONEncoder().encode(d)) == d)
    }

    @Test func exportSizesAreEvenNeverUpscaledAndKeepAspect() {
        var o = VideoExportOptions(); o.resolution = .p720
        let big = o.outputSize(for: CGSize(width: 3840, height: 2160))
        #expect(big == CGSize(width: 1280, height: 720))
        let portrait = o.outputSize(for: CGSize(width: 1080, height: 1920))
        #expect(portrait.width.truncatingRemainder(dividingBy: 2) == 0 && portrait.height == 1280)
        #expect(o.outputSize(for: CGSize(width: 640, height: 360)) == CGSize(width: 640, height: 360))      // no upscaling
        #expect(o.outputSize(for: .zero) == .zero)
    }

    @Test func fpsFallsBackToThirtyWhenUnsupported() {
        var o = VideoExportOptions(); o.fps = 17
        #expect(o.normalizedFPS == 30)
        o.fps = 60; #expect(o.normalizedFPS == 60)
    }
}
