import Foundation
import Testing
@testable import Lumi

struct ToolCatalogTests {
    @Test func idsAreUniqueAndFieldsFilled() {
        #expect(Set(ToolCatalog.all.map(\.id)).count == ToolCatalog.all.count)
        #expect(ToolCatalog.all.allSatisfy { !$0.name.isEmpty && !$0.symbol.isEmpty && !$0.keywords.isEmpty })
    }

    @Test func emptyQueryReturnsEverything() {
        #expect(ToolCatalog.search("").count == ToolCatalog.all.count)
        #expect(ToolCatalog.search("   ").count == ToolCatalog.all.count)
    }

    @Test func matchesNamesAndKeywordsIgnoringCase() {
        #expect(ToolCatalog.search("CROP").first?.id == "crop")
        #expect(ToolCatalog.search("erase").map(\.id) == ["remove"])
        #expect(ToolCatalog.search("passport").first?.id == "id-photo")
        #expect(ToolCatalog.search("zzzz").isEmpty)
    }

    @Test func namesRankAboveKeywords() {
        // "text" is Text's name; Collage has no such keyword, and Text should come first
        #expect(ToolCatalog.search("text").first?.id == "text")
        let r = ToolCatalog.search("crop")
        #expect(r.first?.id == "crop")
    }

    @Test func japaneseKeywordsAndFullWidthWork() {
        #expect(ToolCatalog.search("切り抜き").first?.id == "cutout")
        #expect(ToolCatalog.search("ＰＤＦ").first?.id == "scanner")           // full-width latin matches
    }

    @Test func groupingCoversEveryToolOnce() {
        let g = ToolCatalog.grouped()
        #expect(g.flatMap(\.1).count == ToolCatalog.all.count)
        #expect(ToolCatalog.grouped([]).isEmpty)
    }

    @Test func recentsAreNewestFirstDedupedAndCapped() {
        var r = RecentTools()
        for i in 0..<12 { r.used("t\(i)") }
        #expect(r.ids.count == RecentTools.limit && r.ids.first == "t11")
        r.used("t5"); r.used("t5")
        #expect(r.ids.first == "t5" && r.ids.filter { $0 == "t5" }.count == 1)
    }
}
