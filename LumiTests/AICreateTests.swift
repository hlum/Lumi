import Testing
@testable import Lumi

struct AICreateTests {
    @Test func everyKindHasStarterPrompts() {
        for k in AICreateView.Kind.allCases { #expect(!(AICreateView.prompts[k] ?? []).isEmpty) }
    }

    @Test func toolIsInCatalogAndSearchable() {
        #expect(ToolCatalog.all.contains { $0.id == "ai-create" })
    }
}
