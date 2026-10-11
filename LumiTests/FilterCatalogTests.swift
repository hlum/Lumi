import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FilterCatalogTests {
    static let lib = FilterLibrary.shared

    @Test func catalogHasAboutSixtyFiltersWithUniqueIds() {
        #expect(Self.lib.entries.count >= 60)
        #expect(Set(Self.lib.entries.map(\.id)).count == Self.lib.entries.count)
    }

    @Test func coversTheCategoriesFromThePlan() {
        let cats = Set(Self.lib.categories)
        for c in ["basics", "flash", "film", "camera", "japanese", "cinema", "chinese"] { #expect(cats.contains(c), "\(c)") }
    }

    @Test(arguments: FilterLibrary.shared.entries.map(\.id))
    func everyBundledLUTLoadsAndIsFinite(id: String) throws {
        let l = try #require(Self.lib.lut(id), "failed to load \(id)")
        #expect(l.size == 16 && l.rgb.count == 16 * 16 * 16 * 3)
        #expect(l.rgb.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
    }

    @Test func everyEntryHasNamesInBothLanguagesAndALocalizedKey() throws {
        let ja = try #require(LocalizationTests.bundle("ja"))
        for e in Self.lib.entries {
            #expect(!e.name.isEmpty && !e.nameJa.isEmpty && !e.category.isEmpty, "\(e.id)")
            #expect(ja.localizedString(forKey: e.name, value: "__missing__", table: nil) != "__missing__", "no ja string for \(e.name)")
        }
    }

    @Test func looksActuallyDifferFromEachOtherAndFromNothing() throws {
        let probe = (Float(0.6), Float(0.45), Float(0.35))
        var outputs = Set<String>()
        for e in Self.lib.entries {
            let o = try #require(Self.lib.lut(e.id)).sample(probe.0, probe.1, probe.2)
            #expect(abs(o.0 - probe.0) + abs(o.1 - probe.1) + abs(o.2 - probe.2) > 0.01, "\(e.id) does nothing")
            outputs.insert(String(format: "%.2f,%.2f,%.2f", o.0, o.1, o.2))
        }
        #expect(outputs.count >= Self.lib.entries.count * 3 / 4)
    }

    @Test func monoLooksProduceGray() throws {
        let o = try #require(Self.lib.lut("mono")).sample(0.8, 0.3, 0.2)
        #expect(abs(o.0 - o.1) < 0.02 && abs(o.1 - o.2) < 0.02)
    }

    @Test func warmIsWarmerThanCool() throws {
        let w = try #require(Self.lib.lut("warm")).sample(0.5, 0.5, 0.5), c = try #require(Self.lib.lut("cool")).sample(0.5, 0.5, 0.5)
        #expect(w.0 - w.2 > c.0 - c.2)
    }

    @Test func unknownIdIsNil() { #expect(Self.lib.lut("nope") == nil && Self.lib.entry("nope") == nil) }

    @Test func filterIsADocumentOperationThatRenders() throws {
        var d = EditDocument()
        d.filter = ("warm", 1)
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).filter?.id == "warm")
        let img = RendererTests.solid(0.5, size: 16)
        let out = Renderer.render(img, document: d)
        #expect(GeometryTests.rgb(out, x: 4, y: 4)[0] > GeometryTests.rgb(out, x: 4, y: 4)[2])
        d.filter = ("warm", 7); #expect(d.filter?.intensity == 1)
        d.filter = nil; #expect(d.operations.isEmpty)
        d.filter = ("missing-id", 1)
        #expect(RendererTests.pixel(Renderer.render(img, document: d)) == RendererTests.pixel(img))   // unknown filter is a no-op
    }

    @Test func missingDirectoryGivesEmptyLibraryNotACrash() {
        let l = FilterLibrary(directory: URL(fileURLWithPath: "/nonexistent"))
        #expect(l.entries.isEmpty && l.lut("clean") == nil && l.categories.isEmpty)
    }
}
