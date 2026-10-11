import Foundation

struct FilterEntry: Codable, Equatable, Identifiable {
    var id: String
    var file: String
    var name: String
    var nameJa: String
    var category: String
    var info: FilterInfo { FilterInfo(id: id, name: name, category: category.capitalized) }
}

/// The bundled filter pack: catalog plus lazily parsed, cached LUTs.
final class FilterLibrary {
    nonisolated(unsafe) static let shared = FilterLibrary()

    let entries: [FilterEntry]
    private let directory: URL?
    private var luts: [String: LUT] = [:]
    private let lock = NSLock()

    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Content/Filters")) {
        self.directory = directory
        entries = directory.flatMap { try? Data(contentsOf: $0.appendingPathComponent("catalog.json")) }
            .flatMap { try? JSONDecoder().decode([FilterEntry].self, from: $0) } ?? []
    }

    func entry(_ id: String) -> FilterEntry? { entries.first { $0.id == id } }

    func lut(_ id: String) -> LUT? {
        lock.lock(); defer { lock.unlock() }
        if let l = luts[id] { return l }
        guard let e = entry(id), let dir = directory,
              let text = try? String(contentsOf: dir.appendingPathComponent(e.file), encoding: .utf8),
              let l = try? LUT.parse(cube: text) else { return nil }
        luts[id] = l
        return l
    }

    var categories: [String] { var seen = Set<String>(); return entries.map(\.category).filter { seen.insert($0).inserted } }
    func entries(in category: String) -> [FilterEntry] { entries.filter { $0.category == category } }
}
