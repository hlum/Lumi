import CoreImage
import Foundation
import Testing
@testable import Lumi

struct VideoExtrasTests {
    @Test func coverCandidatesAvoidTheEnds() {
        let c = VideoCover.candidates(duration: 8, count: 4)
        #expect(c == [1, 3, 5, 7] && VideoCover.candidates(duration: 0).isEmpty && VideoCover.candidates(duration: 5, count: 0).isEmpty)
        #expect(VideoCover(time: 99).clampedTime(duration: 10) < 10 && VideoCover(time: -3).clampedTime(duration: 10) == 0)
    }

    @Test func coverCropMatchesAspect() {
        let f = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let out = VideoCover(aspect: 0.75).crop(f)
        #expect(abs(out.extent.width / out.extent.height - 0.75) < 0.01 && out.extent.origin == .zero)
        #expect(VideoCover(aspect: 1, zoom: 2).crop(f).extent.width == 150)
    }

    @Test func collageDurationIsCappedAndShortClipsLoopOrHold() {
        var v = VideoCollage(layout: .grid(rows: 1, cols: 2), clipDurations: [30, 5])
        #expect(v.duration == 20)
        #expect(v.sourceTime(slot: 1, at: 7) == 2 && v.sourceTime(slot: 0, at: 7) == 7)
        v.loopShort = false
        #expect(v.sourceTime(slot: 1, at: 7)! < 5 && v.sourceTime(slot: 1, at: 7)! > 4.9)
        #expect(v.sourceTime(slot: 0, at: 20) == nil && v.sourceTime(slot: 5, at: 1) == nil && v.sourceTime(slot: 0, at: -1) == nil)
    }

    @Test func collageFrameFillsEverySlot() {
        let v = VideoCollage(layout: .grid(rows: 1, cols: 2, gap: 0), clipDurations: [3, 3])
        let a = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        let f = v.frame(at: 1, frames: [a, b], width: 100)!
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        func px(_ x: Int) -> [UInt8] { var p = [UInt8](repeating: 0, count: 4); ctx.render(f, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: x, y: 50, width: 1, height: 1), format: .RGBA8, colorSpace: nil); return p }
        #expect(px(20)[0] > 200 && px(80)[2] > 200)
        #expect(v.frame(at: 5, frames: [a, b], width: 100) == nil && v.frame(at: 1, frames: [], width: 100) == nil)
    }

    @Test func cacheManagerMeasuresAndClearsButKeepsFolders() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        for d in [a, b] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try Data(count: 400).write(to: a.appendingPathComponent("x")); try Data(count: 600).write(to: b.appendingPathComponent("y"))
        let m = CacheManager(roots: [("A", a), ("B", b), ("Gone", root.appendingPathComponent("gone"))])
        #expect(m.entries().map(\.bytes) == [400, 600, 0] && m.total == 1000)
        #expect(m.clear("A") == 400 && fm.fileExists(atPath: a.path) && CacheManager.size(of: a) == 0)
        #expect(m.clear("nope") == 0 && m.clearAll() == 600)
        #expect(CacheManager.formatted(0).isEmpty == false)
    }
}
