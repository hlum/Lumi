import Foundation
import Testing
@testable import Lumi

struct RecipeTests {
    static func doc() -> EditDocument {
        var d = EditDocument()
        d.exposure = 0.5; d.adjust = AdjustParams(saturation: 0.3); d.crop = CropSpec(quarterTurns: 1)
        return d
    }

    @Test func savesWholeStack() {
        #expect(Recipe(name: "all", from: Self.doc()).operations.count == 3)
    }

    @Test func savesOnlyChosenCategories() {
        let r = Recipe(name: "color", from: Self.doc(), categories: [.color])
        #expect(r.categories == [.color] && r.operations.count == 2)
        #expect(Recipe(name: "geo", from: Self.doc(), categories: [.geometry]).operations == [.crop(CropSpec(quarterTurns: 1))])
        #expect(Recipe(name: "none", from: Self.doc(), categories: [.beauty]).operations.isEmpty)
    }

    @Test func applyReplacesSameKindAndKeepsTheRest() {
        var target = EditDocument(); target.exposure = -1; target.crop = CropSpec(flipH: true)
        let out = Recipe(name: "r", operations: [.exposure(0.4)]).apply(to: target)
        #expect(out.exposure == 0.4 && out.crop == CropSpec(flipH: true))
        #expect(out.operations.count == 2)
    }

    @Test func applyCanBeLimitedToSubset() {
        let r = Recipe(name: "all", from: Self.doc())
        let out = r.apply(to: EditDocument(), categories: [.color])
        #expect(out.crop.isIdentity && out.exposure == 0.5)
    }

    @Test func applyIsIdempotent() {
        let r = Recipe(name: "r", from: Self.doc())
        let once = r.apply(to: EditDocument())
        #expect(r.apply(to: once) == once)
    }

    @Test func fileRoundTripGivesNewIdentity() throws {
        var r = Recipe(name: "mine", from: Self.doc()); r.isFavorite = true
        let back = try Recipe.importData(r.exportData())
        #expect(back.name == "mine" && back.operations == r.operations)
        #expect(back.id != r.id && !back.isFavorite)
    }

    @Test func importRejectsGarbageAndNewerVersions() {
        #expect(throws: Recipe.ImportError.notARecipe) { try Recipe.importData(Data("nope".utf8)) }
        #expect(throws: Recipe.ImportError.notARecipe) { try Recipe.importData(Data("{}".utf8)) }
        let newer = #"{"version":99,"recipe":{"id":"00000000-0000-0000-0000-000000000000","name":"x","operations":[],"isFavorite":false}}"#
        #expect(throws: Recipe.ImportError.newerVersion) { try Recipe.importData(Data(newer.utf8)) }
    }

    @Test func storeManagesRecipes() {
        var s = RecipeStore()
        let a = Recipe(name: "Sunset", operations: []), b = Recipe(name: "Mono", operations: [])
        s.add(a); s.add(b)
        s.rename(a.id, to: "Golden hour"); #expect(s.recipes[0].name == "Golden hour")
        s.rename(a.id, to: "  "); #expect(s.recipes[0].name == "Golden hour")
        s.toggleFavorite(b.id); #expect(s.favorites.map(\.id) == [b.id])
        #expect(s.search("GOLD").map(\.id) == [a.id] && s.search("").count == 2 && s.search("zzz").isEmpty)
        s.delete(a.id); #expect(s.recipes.count == 1)
        s.delete(UUID()); s.rename(UUID(), to: "x"); s.toggleFavorite(UUID()); s.markUsed(UUID())
    }

    @Test func recentsAreNewestFirstAndCappedAt50() {
        var s = RecipeStore()
        let ids = (0..<60).map { i -> UUID in let r = Recipe(name: "r\(i)", operations: []); s.add(r); return r.id }
        for (i, id) in ids.enumerated() { s.markUsed(id, at: Date(timeIntervalSince1970: Double(i))) }
        #expect(s.recents.count == RecipeStore.maxRecents)
        #expect(s.recents.first?.id == ids[59] && s.recents.last?.id == ids[10])
    }

    @Test func unusedRecipesAreNotRecents() {
        var s = RecipeStore(); s.add(Recipe(name: "a", operations: []))
        #expect(s.recents.isEmpty)
    }

    @Test func startersAreUsableAndApplyCleanly() {
        #expect(!RecipeStore.starters.isEmpty)
        for r in RecipeStore.starters {
            #expect(!r.operations.isEmpty && !r.name.isEmpty)
            #expect(r.apply(to: EditDocument()) != EditDocument())
        }
    }

    @Test func storePersistsThroughJSON() throws {
        var s = RecipeStore(); s.add(Recipe(name: "a", from: Self.doc()))
        #expect(try JSONDecoder().decode(RecipeStore.self, from: JSONEncoder().encode(s)) == s)
    }
}
