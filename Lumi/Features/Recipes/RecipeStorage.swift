import Foundation
import Observation

/// Keeps the user's recipes in one JSON file and the starter set alongside.
@Observable @MainActor
final class RecipeLibrary {
    private(set) var store: RecipeStore
    private let url: URL?

    nonisolated static var defaultURL: URL { URL.applicationSupportDirectory.appendingPathComponent("recipes.json") }

    init(url: URL? = RecipeLibrary.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(RecipeStore.self, from: data) { store = s } else { store = RecipeStore() }
    }

    var starters: [Recipe] { RecipeStore.starters }
    var mine: [Recipe] { store.recipes }

    func save(name: String, from doc: EditDocument, categories: Set<RecipeCategory>? = nil) -> Recipe? {
        let n = name.trimmingCharacters(in: .whitespaces)
        let r = Recipe(name: n.isEmpty ? "Recipe \(store.recipes.count + 1)" : n, from: doc, categories: categories)
        guard !r.operations.isEmpty else { return nil }               // nothing to save
        store.add(r); persist(); return r
    }

    func rename(_ id: UUID, to name: String) { store.rename(id, to: name); persist() }
    func delete(_ id: UUID) { store.delete(id); persist() }
    func toggleFavorite(_ id: UUID) { store.toggleFavorite(id); persist() }
    func markUsed(_ id: UUID) { store.markUsed(id); persist() }

    /// Brings in a shared recipe file.
    func importFile(_ data: Data) throws -> Recipe {
        let r = try Recipe.importData(data)
        store.add(r); persist(); return r
    }

    private func persist() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(store).write(to: url, options: .atomic)
    }
}
