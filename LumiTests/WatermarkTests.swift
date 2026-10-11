import Foundation
import Testing
@testable import Lumi

struct WatermarkTests {
    @Test func tiledCentersCoverTheFrameAndStagger() {
        let c = WatermarkMath.tileCenters(imageAspect: 1, markAspect: 2, size: 0.2, spacing: 1.5)
        #expect(!c.isEmpty)
        #expect(c.contains { $0.x < 0.35 && $0.y < 0.35 } && c.contains { $0.x > 0.65 && $0.y > 0.65 })
        let ys = Set(c.map(\.y)).sorted()
        let firstRow = c.filter { $0.y == ys[0] }.map(\.x).min()!, secondRow = c.filter { $0.y == ys[1] }.map(\.x).min()!
        #expect(secondRow > firstRow)         // odd rows are offset
    }

    @Test func degenerateInputsGiveNoTiles() {
        #expect(WatermarkMath.tileCenters(imageAspect: 0, markAspect: 1, size: 0.1, spacing: 1).isEmpty)
        #expect(WatermarkMath.tileCenters(imageAspect: 1, markAspect: 1, size: 0, spacing: 1).isEmpty)
        #expect(WatermarkMath.tileCenters(imageAspect: 1, markAspect: 1, size: 0.1, spacing: -1).isEmpty)
    }

    @Test func tinyMarksAreCapped() {
        #expect(WatermarkMath.tileCenters(imageAspect: 1, markAspect: 1, size: 0.0001, spacing: 1).count <= 5_100)
    }

    @Test func largerMarkMeansFewerTiles() {
        let a = WatermarkMath.tileCenters(imageAspect: 1, markAspect: 1, size: 0.1, spacing: 1.5).count
        let b = WatermarkMath.tileCenters(imageAspect: 1, markAspect: 1, size: 0.3, spacing: 1.5).count
        #expect(b < a)
    }

    @Test func threeTimeStampStyles() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 3, minute: 20))!
        #expect(TimeStampStyle.allCases.count == 3)
        #expect(WatermarkMath.timeStamp(d, style: .film, calendar: cal) == "'26 10 03")
        #expect(WatermarkMath.timeStamp(d, style: .digital, calendar: cal) == "2026/10/03 03:20")
        #expect(WatermarkMath.timeStamp(d, style: .plain, calendar: cal) == "2026-10-03")
    }

    @Test func libraryAddsReplacesAndDeletes() throws {
        var lib = WatermarkLibrary()
        var w = Watermark(name: "me", kind: .text("© me"))
        lib.save(w); #expect(lib.items.count == 1)
        w.opacity = 0.9; lib.save(w)
        #expect(lib.items.count == 1 && lib.items[0].opacity == 0.9)
        lib.delete(w.id); #expect(lib.items.isEmpty)
    }

    @Test func libraryPersistsThroughJSON() throws {
        var lib = WatermarkLibrary()
        lib.save(Watermark(name: "a", kind: .image("logo"), isTiled: true))
        #expect(try JSONDecoder().decode(WatermarkLibrary.self, from: JSONEncoder().encode(lib)) == lib)
    }
}
