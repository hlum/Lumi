import Foundation

/// A saved set of operations that can be applied to another photo.
struct Recipe: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var operations: [EditOperation]
    var isFavorite = false
    var lastUsed: Date?

    /// Saves `document` as a recipe, optionally only some categories ("just the color grade").
    init(name: String, from document: EditDocument, categories: Set<RecipeCategory>? = nil) {
        self.name = name
        operations = document.operations.filter { categories?.contains($0.category) ?? true }
    }
    init(name: String, operations: [EditOperation]) { self.name = name; self.operations = operations }

    func apply(to document: EditDocument, categories: Set<RecipeCategory>? = nil) -> EditDocument {
        document.applying(operations.filter { categories?.contains($0.category) ?? true })
    }

    var categories: Set<RecipeCategory> { Set(operations.map(\.category)) }

    // File sharing
    static let fileExtension = "lumirecipe"
    enum ImportError: Error, Equatable { case notARecipe, newerVersion }
    private struct File: Codable { var version: Int; var recipe: Recipe }
    private static let currentVersion = 1

    func exportData() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return try e.encode(File(version: Self.currentVersion, recipe: self))
    }
    static func importData(_ data: Data) throws -> Recipe {
        guard let f = try? JSONDecoder().decode(File.self, from: data) else { throw ImportError.notARecipe }
        guard f.version <= currentVersion else { throw ImportError.newerVersion }
        var r = f.recipe; r.id = UUID(); r.isFavorite = false     // imported recipes are new, not overwrites
        return r
    }
}

struct RecipeStore: Codable, Equatable {
    static let maxRecents = 50
    private(set) var recipes: [Recipe] = []

    mutating func add(_ r: Recipe) { recipes.append(r) }
    mutating func rename(_ id: UUID, to name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, let i = recipes.firstIndex(where: { $0.id == id }) else { return }
        recipes[i].name = name
    }
    mutating func delete(_ id: UUID) { recipes.removeAll { $0.id == id } }
    mutating func toggleFavorite(_ id: UUID) {
        if let i = recipes.firstIndex(where: { $0.id == id }) { recipes[i].isFavorite.toggle() }
    }
    mutating func markUsed(_ id: UUID, at date: Date = .now) {
        if let i = recipes.firstIndex(where: { $0.id == id }) { recipes[i].lastUsed = date }
    }

    var favorites: [Recipe] { recipes.filter(\.isFavorite) }
    /// Most recently used first, at most 50.
    var recents: [Recipe] {
        Array(recipes.filter { $0.lastUsed != nil }.sorted { $0.lastUsed! > $1.lastUsed! }.prefix(Self.maxRecents))
    }
    func search(_ q: String) -> [Recipe] {
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        return t.isEmpty ? recipes : recipes.filter { $0.name.lowercased().contains(t) }
    }

    /// Recipes shipped with the app.
    static let starters: [Recipe] = [
        Recipe(name: "Warm glow", operations: [.adjust(AdjustParams.presets["warm"]!)]),
        Recipe(name: "Cool tone", operations: [.adjust(AdjustParams.presets["cool"]!)]),
        Recipe(name: "Vivid pop", operations: [.adjust(AdjustParams.presets["vivid"]!), .curve(ToneCurve.presets["contrast"]!)]),
        Recipe(name: "Soft fade", operations: [.curve(ToneCurve.presets["fade"]!), .exposure(0.2)]),
    ]
}
