import Foundation
import Testing
@testable import Lumi

struct CaptionTests {
    func track() -> CaptionTrack {
        var t = CaptionTrack()
        t.captions = [Caption(start: 0, end: 2, text: "hello there my friend"), Caption(start: 2, end: 4.5, text: "how are you")]
        return t
    }

    @Test func srtTimestampsAreFormattedAndRoundTrip() {
        #expect(SRT.timestamp(3725.5) == "01:02:05,500" && SRT.timestamp(-1) == "00:00:00,000" && SRT.timestamp(0.0004) == "00:00:00,000")
        #expect(SRT.seconds("01:02:05,500") == 3725.5 && SRT.seconds("bad") == nil && SRT.seconds("00:01") == nil)
    }

    @Test func exportsNumberedBlocksAndParsesThemBack() {
        let t = track(), srt = SRT.export(t)
        #expect(srt.hasPrefix("1\n00:00:00,000 --> 00:00:02,000\nhello there my friend\n\n2\n"))
        let back = SRT.parse(srt)
        #expect(back.map(\.text) == t.captions.map(\.text) && back.map(\.start) == [0, 2] && back.map(\.end) == [2, 4.5])
    }

    @Test func bilingualExportAddsTheSecondLine() {
        var t = track(); t.applyTranslations(["こんにちは"]); t.style.bilingual = true
        #expect(SRT.export(t).contains("hello there my friend\nこんにちは"))
        t.style.bilingual = false
        #expect(!SRT.export(t).contains("こんにちは"))
    }

    @Test func parserSkipsBrokenBlocksAndHandlesWindowsLineEndings() {
        let text = "1\r\n00:00:01,000 --> 00:00:02,000\r\nfine\r\n\r\n2\r\nnot a time\r\nbroken\r\n\r\n3\r\n00:00:05,000 --> 00:00:04,000\r\nbackwards\r\n\r\n4\r\n00:00:06,000 --> 00:00:07,000\r\nline one\r\nline two"
        let c = SRT.parse(text)
        #expect(c.map(\.text) == ["fine", "line one\nline two"])
        #expect(SRT.parse("").isEmpty)
    }

    @Test func lookupEditSplitMerge() {
        var t = track()
        #expect(t.caption(at: 1)?.text.hasPrefix("hello") == true && t.caption(at: 2)?.text == "how are you" && t.caption(at: 9) == nil)
        let id = t.captions[0].id
        t.edit(id, text: "hi there my friend"); #expect(t.captions[0].text == "hi there my friend")
        t.split(id, at: 1)
        #expect(t.captions.count == 3 && t.captions[0].text == "hi there" && t.captions[1].text == "my friend" && t.captions[0].end == t.captions[1].start)
        t.split(id, at: 99); #expect(t.captions.count == 3)                  // outside: ignored
        t.merge(t.captions[0].id)
        #expect(t.captions.count == 2 && t.captions[0].text == "hi there my friend" && t.captions[0].end == 2)
        t.merge(t.captions[1].id); #expect(t.captions.count == 2)           // last has nothing to merge with
    }

    @Test func shiftNeverGoesNegative() {
        var t = track(); t.shift(by: -1)
        #expect(t.captions[0].start == 0 && t.captions[0].end == 1 && t.captions[1].start == 1)
    }

    @Test func teleprompterPacesTheScript() {
        let p = Teleprompter(script: "one two three four five six", wordsPerMinute: 60)    // one word a second
        #expect(p.duration == 6 && p.currentWord(at: 0) == 0 && p.currentWord(at: 2.5) == 2 && p.currentWord(at: 99) == 5 && p.currentWord(at: -3) == 0)
        #expect(p.progress(at: 3) == 0.5 && p.progress(at: 100) == 1)
        let w = p.window(at: 2.5, before: 2, after: 2)
        #expect(w.read == ["one", "two"] && w.current == "three" && w.next == ["four", "five"])
        let empty = Teleprompter(script: "  ")
        #expect(empty.duration == 0 && empty.window(at: 1).current == nil && empty.progress(at: 1) == 0)
    }
}
