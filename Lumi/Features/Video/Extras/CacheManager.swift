import Foundation

/// Disk the app creates and can safely rebuild: previews, exports, thumbnails, model scratch.
struct CacheManager {
    struct Entry: Equatable, Identifiable { var name: String; var url: URL; var bytes: Int; var id: String { name } }
    var roots: [(name: String, url: URL)]
    var fm: FileManager = .default

    static var standard: CacheManager {
        let fm = FileManager.default
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return CacheManager(roots: [("Previews", caches.appendingPathComponent("previews")), ("Exports", fm.temporaryDirectory.appendingPathComponent("exports")), ("Thumbnails", caches.appendingPathComponent("thumbnails"))])
    }

    static func size(of url: URL, fm: FileManager = .default) -> Int {
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return e.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)
    }

    func entries() -> [Entry] { roots.map { Entry(name: $0.name, url: $0.url, bytes: Self.size(of: $0.url, fm: fm)) } }
    var total: Int { entries().map(\.bytes).reduce(0, +) }

    /// Empties the folder but keeps it. Returns bytes freed.
    @discardableResult func clear(_ name: String) -> Int {
        guard let root = roots.first(where: { $0.name == name }) else { return 0 }
        let before = Self.size(of: root.url, fm: fm)
        for u in (try? fm.contentsOfDirectory(at: root.url, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: u) }
        return before - Self.size(of: root.url, fm: fm)
    }

    @discardableResult func clearAll() -> Int { roots.map { clear($0.name) }.reduce(0, +) }

    static func formatted(_ bytes: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
}
