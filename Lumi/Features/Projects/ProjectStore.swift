import Foundation
import SwiftData

/// Drafts: SwiftData record + original file on disk. Originals live in `directory`.
@MainActor
struct ProjectStore {
    let context: ModelContext
    let directory: URL

    static var defaultDirectory: URL { URL.applicationSupportDirectory.appendingPathComponent("Originals", isDirectory: true) }

    @discardableResult
    func create(original: Data, now: Date = .now) throws -> Project {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".img"
        try original.write(to: directory.appendingPathComponent(name))
        let p = try Project(originalFileName: name, now: now)
        context.insert(p)
        try context.save()
        return p
    }

    func save(_ document: EditDocument, to p: Project, thumbnail: Data? = nil, now: Date = .now) throws {
        p.documentJSON = try JSONEncoder().encode(document)
        p.updatedAt = now
        if let thumbnail { p.thumbnail = thumbnail }
        try context.save()
    }

    /// Newest first.
    func all() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    func originalURL(_ p: Project) -> URL { directory.appendingPathComponent(p.originalFileName) }
    func hasOriginal(_ p: Project) -> Bool { FileManager.default.fileExists(atPath: originalURL(p).path) }

    func duplicate(_ p: Project, now: Date = .now) throws -> Project {
        let data = try Data(contentsOf: originalURL(p))
        let copy = try create(original: data, now: now)
        try save(p.document, to: copy, thumbnail: p.thumbnail, now: now)
        return copy
    }

    func delete(_ p: Project) throws {
        try? FileManager.default.removeItem(at: originalURL(p))
        context.delete(p)
        try context.save()
    }
}

/// Connects one open photo to its draft: creates the record when a photo is opened and saves after every edit.
@MainActor
final class ProjectSession {
    let store: ProjectStore
    private(set) var project: Project?

    init(store: ProjectStore, project: Project? = nil) { self.store = store; self.project = project }

    /// Starts a draft for freshly picked photo data.
    func begin(original: Data) throws { project = try store.create(original: original) }

    /// Original bytes and saved edits of an existing draft; nil if the original file is gone.
    func load() -> (data: Data, document: EditDocument)? {
        guard let p = project, store.hasOriginal(p), let d = try? Data(contentsOf: store.originalURL(p)) else { return nil }
        return (d, p.document)
    }

    func save(_ document: EditDocument, thumbnail: Data?) {
        guard let p = project else { return }
        try? store.save(document, to: p, thumbnail: thumbnail)
    }
}
