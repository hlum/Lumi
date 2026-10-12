import Foundation

/// One browsable item in the material center.
struct Material: Equatable, Identifiable, Hashable {
    enum Kind: String, CaseIterable, Codable { case sticker, filter, font, frame, background }
    var kind: Kind
    var itemID: String
    var name: String
    var category: String
    var keywords: [String] = []
    var id: String { "\(kind.rawValue):\(itemID)" }
}

/// A hand-picked group; seasonal packs list the months (1...12) they are surfaced in.
struct MaterialCollection: Equatable, Identifiable {
    var id: String
    var name: String
    var itemIDs: [String]            // Material.id values
    var months: [Int] = []
    var isSeasonal: Bool { !months.isEmpty }
}

struct MaterialCatalog {
    var materials: [Material]
    var collections: [MaterialCollection]
    var favorites: Set<String> = []      // "My materials", Material.id values

    /// Everything bundled: stickers, filters and fonts from their libraries, plus built-in frames and backgrounds.
    static func bundled(stickers: [StickerInfo] = StickerLibrary.all, filters: [FilterEntry] = FilterLibrary.shared.entries, fonts: [BundledFont] = FontLibrary.all, frames: [String] = FrameConfig.Style.allCases.map(\.rawValue)) -> MaterialCatalog {
        var m: [Material] = []
        m += stickers.map { Material(kind: .sticker, itemID: $0.id, name: $0.name, category: $0.category, keywords: $0.keywords) }
        m += filters.map { Material(kind: .filter, itemID: $0.id, name: $0.name, category: $0.category.capitalized) }
        m += fonts.map { Material(kind: .font, itemID: $0.postScript, name: $0.name, category: "Fonts") }
        m += frames.map { Material(kind: .frame, itemID: $0, name: $0.capitalized, category: "Frames") }
        m += BackgroundSwatch.all.map { Material(kind: .background, itemID: $0.id, name: $0.name, category: "Backgrounds") }
        let ids = Set(m.map(\.id))
        let wanted: [MaterialCollection] = [
            .init(id: "love", name: "Love", itemIDs: ["sticker:heart", "sticker:star"], months: [2]),
            .init(id: "summer", name: "Summer", itemIDs: ["sticker:sun", "sticker:flower"], months: [6, 7, 8]),
            .init(id: "winter", name: "Winter", itemIDs: ["sticker:snowflake", "sticker:star"], months: [12, 1]),
            .init(id: "clean", name: "Clean and bright", itemIDs: ["background:white", "background:cream"]),
        ]
        // keep only entries that exist, so a collection never points at nothing
        let cols = wanted.map { c in var c = c; c.itemIDs = c.itemIDs.filter(ids.contains); return c }.filter { !$0.itemIDs.isEmpty }
        return MaterialCatalog(materials: m, collections: cols)
    }

    var categories: [String] { var s = Set<String>(); return materials.map(\.category).filter { s.insert($0).inserted } }

    func items(kind: Material.Kind? = nil, category: String? = nil, query: String = "") -> [Material] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return materials.filter { m in
            (kind == nil || m.kind == kind) && (category == nil || m.category == category)
                && (q.isEmpty || m.name.lowercased().contains(q) || m.category.lowercased().contains(q) || m.keywords.contains { $0.lowercased().contains(q) })
        }
    }

    var mine: [Material] { materials.filter { favorites.contains($0.id) } }
    mutating func toggleFavorite(_ m: Material) { if !favorites.insert(m.id).inserted { favorites.remove(m.id) } }

    func seasonal(month: Int) -> [MaterialCollection] { collections.filter { $0.months.contains(month) } }
    func items(in c: MaterialCollection) -> [Material] { c.itemIDs.compactMap { id in materials.first { $0.id == id } } }
}

struct BackgroundSwatch: Equatable { var id: String; var name: String; var color: RGBA
    static let all: [BackgroundSwatch] = [
        .init(id: "white", name: "White", color: RGBA(r: 1, g: 1, b: 1, a: 1)), .init(id: "cream", name: "Cream", color: RGBA(r: 0.99, g: 0.96, b: 0.88, a: 1)),
        .init(id: "blush", name: "Blush", color: RGBA(r: 0.98, g: 0.82, b: 0.85, a: 1)), .init(id: "sky", name: "Sky", color: RGBA(r: 0.7, g: 0.85, b: 0.98, a: 1)),
        .init(id: "ink", name: "Ink", color: RGBA(r: 0.08, g: 0.08, b: 0.1, a: 1)),
    ]
}

/// Disk use of the user's own materials, for the storage-management screen.
enum MaterialStorage {
    static func bytes(in directory: URL, fm: FileManager = .default) -> Int {
        guard let en = fm.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return en.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)
    }
}
