import CoreImage
import Foundation
import Testing
@testable import Lumi

@MainActor
struct RecipeLibraryTests {
    static func tempURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("recipes.json") }
    static func doc() -> EditDocument { var d = EditDocument(); d.adjust = AdjustParams(saturation: 0.3); d.filter = ("warm", 0.8); return d }

    @Test func savedRecipesSurviveARelaunch() {
        let url = Self.tempURL()
        let a = RecipeLibrary(url: url)
        let r = a.save(name: "Mine", from: Self.doc())
        #expect(r != nil && a.mine.count == 1)
        let b = RecipeLibrary(url: url)
        #expect(b.mine.map(\.name) == ["Mine"] && b.mine[0].operations == r?.operations)
    }

    @Test func emptyDocumentsAreNotSavedAndBlankNamesGetADefault() {
        let a = RecipeLibrary(url: Self.tempURL())
        #expect(a.save(name: "x", from: EditDocument()) == nil && a.mine.isEmpty)
        #expect(a.save(name: "  ", from: Self.doc())?.name == "Recipe 1")
    }

    @Test func renameFavoriteDeleteAndMarkUsedPersist() {
        let url = Self.tempURL(), a = RecipeLibrary(url: url)
        let r = a.save(name: "A", from: Self.doc())!
        a.rename(r.id, to: "B"); a.toggleFavorite(r.id); a.markUsed(r.id)
        let b = RecipeLibrary(url: url)
        #expect(b.mine[0].name == "B" && b.mine[0].isFavorite && b.mine[0].lastUsed != nil)
        b.delete(r.id); #expect(RecipeLibrary(url: url).mine.isEmpty)
    }

    @Test func sharedFilesImportAsNewRecipes() throws {
        let a = RecipeLibrary(url: Self.tempURL())
        let r = a.save(name: "Share me", from: Self.doc())!
        let file = try r.exportData()
        let b = RecipeLibrary(url: Self.tempURL())
        let imported = try b.importFile(file)
        #expect(imported.name == "Share me" && imported.id != r.id && b.mine.count == 1)
        #expect(throws: Recipe.ImportError.notARecipe) { try b.importFile(Data("junk".utf8)) }
    }

    @Test func corruptStorageFallsBackToEmpty() throws {
        let url = Self.tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(RecipeLibrary(url: url).mine.isEmpty)
        #expect(RecipeLibrary(url: nil).starters.count >= 4)
    }
}

@MainActor
struct BatchModelTests {
    final class Saver: PhotoSaving {
        var saved: [Data] = []; var failOn: Int?
        func save(_ data: Data) async throws { if failOn == saved.count + 1 { failOn = nil; throw EditorError.photosDenied }; saved.append(data) }
    }
    static func photo(_ v: CGFloat) -> Data { CIContext().jpegRepresentation(of: RendererTests.solid(v, size: 40), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)! }
    static let bright = Recipe(name: "Bright", operations: [.adjust(AdjustParams(brightness: 0.8))])

    @Test func appliesTheRecipeToEveryPhotoAndSavesEach() async {
        let s = Saver(), m = BatchModel(saver: s)
        await m.run([("a", Self.photo(0.3)), ("b", Self.photo(0.4)), ("c", Self.photo(0.2))], recipe: Self.bright)
        #expect(s.saved.count == 3 && m.completed == 3 && m.progress == 1 && !m.isRunning)
        #expect(m.items.allSatisfy { $0.status == .done })
        // output is brighter than the input
        let outPx = RendererTests.pixel(CIImage(data: s.saved[0])!), inPx = RendererTests.pixel(CIImage(data: Self.photo(0.3))!)
        #expect(outPx[0] > inPx[0] + 20)
    }

    @Test func oneBadPhotoDoesNotStopTheRest() async {
        let s = Saver(), m = BatchModel(saver: s)
        await m.run([("ok", Self.photo(0.3)), ("bad", Data([1, 2, 3])), ("ok2", Self.photo(0.5))], recipe: Self.bright)
        #expect(s.saved.count == 2 && m.failures.map(\.name) == ["bad"])
        #expect(m.items[0].status == .done && m.items[2].status == .done)
    }

    @Test func aSaveFailureIsReportedPerPhoto() async {
        let s = Saver(); s.failOn = 2
        let m = BatchModel(saver: s)
        await m.run([("a", Self.photo(0.3)), ("b", Self.photo(0.3)), ("c", Self.photo(0.3))], recipe: Self.bright)
        #expect(s.saved.count == 2 && m.failures.map(\.name) == ["b"])
    }

    @Test func emptyBatchIsFineAndCategoriesLimitWhatIsApplied() async {
        let m = BatchModel(saver: Saver())
        await m.run([], recipe: Self.bright)
        #expect(m.items.isEmpty && m.progress == 0)
        let s = Saver(), m2 = BatchModel(saver: s)
        await m2.run([("a", Self.photo(0.3))], recipe: Self.bright, categories: [.geometry])     // brightness is "color": not applied
        let out = RendererTests.pixel(CIImage(data: s.saved[0])!), base = RendererTests.pixel(CIImage(data: Self.photo(0.3))!)
        #expect(abs(Int(out[0]) - Int(base[0])) < 6)
    }
}
