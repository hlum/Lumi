import Testing
@testable import Lumi

struct EditorToolsTests {
    @Test func everyCategoryHasToolsAndNoToolIsListedTwice() {
        var seen: [EditorTool] = []
        for c in EditorCategory.allCases {
            let t = EditorTool.tools(in: c)
            #expect(!t.isEmpty, "\(c)")
            seen += t
        }
        #expect(Set(seen).count == seen.count)
    }

    @Test func toolsSitInTheCategoryTheyAreListedUnder() {
        for c in EditorCategory.allCases { for t in EditorTool.tools(in: c) { #expect(t.category == c, "\(t) listed under \(c) but belongs to \(t.category)") } }
    }

    @Test func faceToolsAreMarkedSoOutlinesAppear() {
        for t in [EditorTool.skin, .reshape, .blemish, .eyesTeeth, .underEye, .lips, .eyeMakeup, .looks, .autoBeauty] { #expect(t.usesFaces, "\(t)") }
        for t in [EditorTool.crop, .adjust, .body, .nails, .hair] { #expect(!t.usesFaces, "\(t)") }
        #expect(EditorTool.allCases.allSatisfy { !$0.symbol.isEmpty })
    }

    @Test func reshapeTabsAllHaveItemsWithUniqueNames() {
        for tab in ReshapePanel.Tab.allCases {
            let items = ReshapePanel.items(tab)
            #expect(!items.isEmpty && Set(items.map(\.id)).count == items.count, "\(tab)")
            // every slider really moves a value in the document
            var f = FaceRetouch()
            for it in items { f[keyPath: it.path] = it.range.upperBound; #expect(f != FaceRetouch(), "\(tab)/\(it.title)"); f = FaceRetouch() }
        }
    }
}
