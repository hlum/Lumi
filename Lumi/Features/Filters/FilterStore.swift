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
