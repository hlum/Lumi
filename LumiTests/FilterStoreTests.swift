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
