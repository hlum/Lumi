import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FilterStoreTests {
    static let all = [FilterInfo(id: "a", name: "Soft Film", category: "Film"), FilterInfo(id: "b", name: "Neon", category: "Night"), FilterInfo(id: "c", name: "CCD Flash", category: "Digicam")]

    @Test func favoriteToggles() {
        var p = FilterPrefs()
        p.toggleFavorite("a"); #expect(p.favorites == ["a"])
        p.toggleFavorite("a"); #expect(p.favorites.isEmpty)
    }

    @Test func recentsAreMostRecentFirstDeduplicatedAndCapped() {
        var p = FilterPrefs()
        for i in 0..<15 { p.used("f\(i)") }
        #expect(p.recents.count == FilterPrefs.maxRecents && p.recents.first == "f14")
        p.used("f10")
        #expect(p.recents.first == "f10" && p.recents.filter { $0 == "f10" }.count == 1)
    }

    @Test func hiddenFiltersAreRemovedFromVisibleAndSearch() {
        var p = FilterPrefs()
        p.setHidden("b", true)
        #expect(p.visible(Self.all).map(\.id) == ["a", "c"])
        #expect(p.search(Self.all, query: "neon").isEmpty)
        p.setHidden("b", false)
        #expect(p.visible(Self.all).count == 3)
    }

    @Test func searchMatchesNameAndCategoryCaseInsensitively() {
        let p = FilterPrefs()
        #expect(p.search(Self.all, query: "FILM").map(\.id) == ["a"])
        #expect(p.search(Self.all, query: "digi").map(\.id) == ["c"])
        #expect(p.search(Self.all, query: "  ").count == 3)
        #expect(p.search(Self.all, query: "zzz").isEmpty)
    }

    @Test func reorderFavoritesAndIgnoreBadIndices() {
        var p = FilterPrefs()
        ["a", "b", "c"].forEach { p.toggleFavorite($0) }
        p.moveFavorite(from: 0, to: 2); #expect(p.favorites == ["b", "c", "a"])
        p.moveFavorite(from: 9, to: 0); #expect(p.favorites == ["b", "c", "a"])
    }

    @Test func favoritesPersistThroughCodable() throws {
        var p = FilterPrefs()
        p.toggleFavorite("a"); p.used("b"); p.setHidden("c", true)
        #expect(try JSONDecoder().decode(FilterPrefs.self, from: JSONEncoder().encode(p)) == p)
    }
}

@MainActor
struct FilterPrefsBoxTests {
    static func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("p.json") }

    @Test func favoritesAndRecentsPersist() {
        let u = Self.url(), a = FilterPrefsBox(url: u)
        a.toggleFavorite("warm"); a.used("cool"); a.used("mono"); a.setHidden("flash", true)
        let b = FilterPrefsBox(url: u)
        #expect(b.isFavorite("warm") && b.prefs.recents == ["mono", "cool"] && b.prefs.hidden.contains("flash"))
        b.toggleFavorite("warm"); #expect(!FilterPrefsBox(url: u).isFavorite("warm"))
    }

    @Test func corruptOrMissingFileStartsFresh() throws {
        #expect(FilterPrefsBox(url: Self.url()).prefs == FilterPrefs() && FilterPrefsBox(url: nil).prefs == FilterPrefs())
        let u = Self.url(); try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: u)
        #expect(FilterPrefsBox(url: u).prefs == FilterPrefs())
    }
}

struct FilterEraserTests {
    static func img() -> CIImage { CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)) }

    @Test func eraserBringsTheOriginalBackWhereBrushed() {
        var d = EditDocument(); d.filter = ("warm", 1)
        var m = MaskCanvas(width: 32, height: 32); m.fill(rect: CGRect(x: 0, y: 0, width: 16, height: 32))        // left half erased
        d.filterEraser = m
        let out = Renderer.render(Self.img(), document: d)
        #expect(GeometryTests.near(GeometryTests.rgb(out, x: 10, y: 32), GeometryTests.rgb(Self.img(), x: 10, y: 32)))       // original gray
        let right = GeometryTests.rgb(out, x: 54, y: 32)
        #expect(right[0] > right[2])                                                                                         // filtered (warm) on the right
    }

    @Test func emptyMaskDropsTheOperationAndRoundTrips() throws {
        var d = EditDocument(); d.filter = ("warm", 0.8)
        d.filterEraser = MaskCanvas(width: 8, height: 8)
        #expect(d.operations.count == 1)                                                                                     // nothing painted: no eraser op
        var m = MaskCanvas(width: 8, height: 8); m.fill(rect: CGRect(x: 0, y: 0, width: 4, height: 8)); d.filterEraser = m
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).filterEraser == m)
        d.filterEraser = nil; #expect(d.operations.count == 1)
    }

    @Test func eraserWithoutAFilterDoesNothing() {
        var d = EditDocument()
        var m = MaskCanvas(width: 8, height: 8); m.fill(rect: CGRect(x: 0, y: 0, width: 8, height: 8)); d.filterEraser = m
        #expect(GeometryTests.near(RendererTests.pixel(Renderer.render(Self.img(), document: d)), RendererTests.pixel(Self.img())))
    }
}
