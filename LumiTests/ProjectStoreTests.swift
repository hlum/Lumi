import Foundation
import SwiftData
import Testing
@testable import Lumi

@MainActor
struct ProjectStoreTests {
    /// A context doesn't keep its container alive; hold them for the whole run.
    static var containers: [ModelContainer] = []

    static func store() throws -> ProjectStore {
        let c = try ModelContainer(for: Project.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        containers.append(c)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return ProjectStore(context: ModelContext(c), directory: dir)
    }
    static let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func createStoresOriginalAndRecord() throws {
        let s = try Self.store()
        let p = try s.create(original: Data([1, 2, 3]))
        #expect(s.hasOriginal(p))
        #expect(try Data(contentsOf: s.originalURL(p)) == Data([1, 2, 3]))
        #expect(try s.all().count == 1)
    }

    @Test func listIsNewestFirst() throws {
        let s = try Self.store()
        let a = try s.create(original: Data([1]), now: Self.t0)
        let b = try s.create(original: Data([2]), now: Self.t0 + 10)
        #expect(try s.all().map(\.id) == [b.id, a.id])
        try s.save(EditDocument(), to: a, now: Self.t0 + 20)   // touching a moves it to the top
        #expect(try s.all().first?.id == a.id)
    }

    @Test func documentSurvivesSaveAndReload() throws {
        let s = try Self.store()
        let p = try s.create(original: Data([1]))
        var d = EditDocument(); d.exposure = 0.8
        try s.save(d, to: p)
        #expect(try s.all().first?.document == d)
    }

    @Test func corruptDocumentFallsBackToEmpty() throws {
        let s = try Self.store()
        let p = try s.create(original: Data([1]))
        p.documentJSON = Data("nope".utf8)
        #expect(p.document == EditDocument())
    }

    @Test func missingOriginalIsDetected() throws {
        let s = try Self.store()
        let p = try s.create(original: Data([1]))
        try FileManager.default.removeItem(at: s.originalURL(p))
        #expect(!s.hasOriginal(p))
        #expect(throws: (any Error).self) { try s.duplicate(p) }
    }

    @Test func duplicateCopiesDocumentAndFile() throws {
        let s = try Self.store()
        let p = try s.create(original: Data([9]))
        var d = EditDocument(); d.exposure = 1
        try s.save(d, to: p, thumbnail: Data([7]))
        let c = try s.duplicate(p)
        #expect(c.id != p.id && c.originalFileName != p.originalFileName)
        #expect(c.document == d && c.thumbnail == Data([7]))
        #expect(try Data(contentsOf: s.originalURL(c)) == Data([9]))
        #expect(try s.all().count == 2)
    }

    @Test func deleteRemovesRecordAndFile() throws {
        let s = try Self.store()
        let p = try s.create(original: Data([1]))
        let url = s.originalURL(p)
        try s.delete(p)
        #expect(try s.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func deleteWithMissingFileStillDeletesRecord() throws {
        let s = try Self.store()
        let p = try s.create(original: Data([1]))
        try FileManager.default.removeItem(at: s.originalURL(p))
        try s.delete(p)
        #expect(try s.all().isEmpty)
    }
}
