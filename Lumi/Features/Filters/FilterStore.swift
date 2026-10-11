import Observation
import Foundation

struct FilterInfo: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var category: String
}

/// Favorites, recents and hidden filters. Plain value type; persist it with Codable.
struct FilterPrefs: Codable, Equatable {
    private(set) var favorites: [String] = []
    private(set) var recents: [String] = []
    private(set) var hidden: Set<String> = []
    static let maxRecents = 10

    mutating func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.append(id) }
    }
    mutating func used(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
    }
    mutating func setHidden(_ id: String, _ isHidden: Bool) {
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
    }
    mutating func moveFavorite(from: Int, to: Int) {
        guard favorites.indices.contains(from), favorites.indices.contains(to) else { return }
        favorites.insert(favorites.remove(at: from), at: to)
    }

    func visible(_ all: [FilterInfo]) -> [FilterInfo] { all.filter { !hidden.contains($0.id) } }

    func search(_ all: [FilterInfo], query: String) -> [FilterInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = visible(all)
        return q.isEmpty ? list : list.filter { $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q) }
    }
}

/// Favorites, recents and hidden filters kept in one JSON file.
@Observable @MainActor
final class FilterPrefsBox {
    private(set) var prefs: FilterPrefs
    private let url: URL?
    nonisolated static var defaultURL: URL { URL.applicationSupportDirectory.appendingPathComponent("filter-prefs.json") }

    init(url: URL? = FilterPrefsBox.defaultURL) {
        self.url = url
        if let url, let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(FilterPrefs.self, from: d) { prefs = p } else { prefs = FilterPrefs() }
    }

    func toggleFavorite(_ id: String) { prefs.toggleFavorite(id); persist() }
    func used(_ id: String) { prefs.used(id); persist() }
    func setHidden(_ id: String, _ h: Bool) { prefs.setHidden(id, h); persist() }
    func isFavorite(_ id: String) -> Bool { prefs.favorites.contains(id) }

    private func persist() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(prefs).write(to: url, options: .atomic)
    }
}
