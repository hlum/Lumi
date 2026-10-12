import CoreImage
import Testing
@testable import Lumi

struct MaterialCatalogTests {
    let cat = MaterialCatalog.bundled(filters: [FilterEntry(id: "f1", file: "f1.cube", name: "Peach", nameJa: "", category: "portrait")], fonts: [BundledFont(name: "Serif", postScript: "Serif-R", file: "s.ttf")])

    @Test func coversEveryKind() {
        for k in Material.Kind.allCases { #expect(!cat.items(kind: k).isEmpty, "\(k)") }
        #expect(Set(cat.materials.map(\.id)).count == cat.materials.count)           // ids unique
    }

    @Test func searchMatchesNameCategoryAndCaseInsensitive() {
        #expect(cat.items(query: "PEACH").map(\.itemID) == ["f1"])
        #expect(cat.items(query: "  ").count == cat.materials.count)
        #expect(cat.items(query: "zzzzzz").isEmpty)
        #expect(cat.items(kind: .filter, category: "Portrait").count == 1)
        #expect(cat.categories.contains("Frames"))
    }

    @Test func myMaterialsToggle() {
        var c = cat; let m = c.materials[0]
        c.toggleFavorite(m); #expect(c.mine == [m])
        c.toggleFavorite(m); #expect(c.mine.isEmpty)
    }

    @Test func collectionsOnlyPointAtRealItemsAndSeasonsFilter() {
        for c in cat.collections { #expect(!c.itemIDs.isEmpty); #expect(cat.items(in: c).count == c.itemIDs.count) }
        #expect(cat.seasonal(month: 2).contains { $0.id == "love" } || !cat.collections.contains { $0.id == "love" })
        #expect(cat.seasonal(month: 4).isEmpty)
    }

    @Test func storageCountsFiles() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try Data(count: 1000).write(to: d.appendingPathComponent("a")); try Data(count: 500).write(to: d.appendingPathComponent("b"))
        #expect(MaterialStorage.bytes(in: d) == 1500)
        #expect(MaterialStorage.bytes(in: d.appendingPathComponent("missing")) == 0)
    }

    @Test func wallpaperFillsTargetExactly() {
        let img = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        for t in WallpaperMaker.targets {
            let out = WallpaperMaker.make(img, target: t, zoom: 2, pan: CGPoint(x: 1, y: -1))
            #expect(out.extent == CGRect(x: 0, y: 0, width: t.width, height: t.height), "\(t.name)")
        }
    }
}
