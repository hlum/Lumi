import CoreImage
import Foundation
import SwiftData
import Testing
@testable import Lumi

@MainActor
struct ProjectSessionTests {
    static func jpeg(_ v: CGFloat = 0.5) -> Data {
        CIContext().jpegRepresentation(of: RendererTests.solid(v, size: 64), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    }

    static func session() throws -> ProjectSession {
        ProjectSession(store: try ProjectStoreTests.store())
    }

    @Test func pickingAPhotoCreatesADraftWithItsOriginal() throws {
        let s = try Self.session()
        let m = EditorModel(saver: EditorModelTests.FakeSaver()); m.session = s
        try m.load(data: Self.jpeg())
        let p = try #require(s.project)
        let count = try s.store.all().count
        #expect(s.store.hasOriginal(p) && count == 1)
    }

    @Test func everyCommittedEditIsSavedWithAThumbnail() throws {
        let s = try Self.session()
        let m = EditorModel(saver: EditorModelTests.FakeSaver()); m.session = s
        try m.load(data: Self.jpeg())
        m.edit { $0.adjust = AdjustParams(brightness: 0.3) }
        let p = try #require(s.project)
        #expect(p.document.adjust.brightness == 0.3)
        #expect(p.thumbnail != nil && (p.thumbnail?.count ?? 0) > 100)
        m.undo()
        #expect(p.document.adjust.isIdentity)                              // undo is saved too
    }

    @Test func reopeningRestoresTheEditsButNotTheWholeUndoHistory() throws {
        let s = try Self.session()
        let m = EditorModel(saver: EditorModelTests.FakeSaver()); m.session = s
        try m.load(data: Self.jpeg())
        m.edit { $0.crop.flipH = true }; m.edit { $0.exposure = 0.4 }
        // "relaunch": a new model on a new session pointing at the same stored project
        let again = EditorModel(saver: EditorModelTests.FakeSaver()); again.session = ProjectSession(store: s.store, project: s.project)
        try again.openDraft()
        #expect(again.document.crop.flipH && again.document.exposure == 0.4)
        #expect(again.original != nil && !again.canUndo)
        again.edit { $0.exposure = 0.9 }
        #expect(again.canUndo)
    }

    @Test func missingOriginalFailsCleanly() throws {
        let s = try Self.session()
        let m = EditorModel(saver: EditorModelTests.FakeSaver()); m.session = s
        try m.load(data: Self.jpeg())
        try FileManager.default.removeItem(at: s.store.originalURL(try #require(s.project)))
        let again = EditorModel(saver: EditorModelTests.FakeSaver()); again.session = ProjectSession(store: s.store, project: s.project)
        #expect(throws: EditorError.undecodable) { try again.openDraft() }
        #expect(s.load() == nil)
    }

    @Test func editorWithoutASessionStillWorks() throws {
        let m = EditorModel(saver: EditorModelTests.FakeSaver())
        try m.load(data: Self.jpeg()); m.edit { $0.exposure = 0.2 }
        #expect(m.document.exposure == 0.2)
        #expect(throws: EditorError.undecodable) { try m.openDraft() }
    }

    @Test func draftsListNewestFirstAfterEdits() throws {
        let store = try ProjectStoreTests.store()
        let a = EditorModel(saver: EditorModelTests.FakeSaver()); a.session = ProjectSession(store: store)
        try a.load(data: Self.jpeg(0.3))
        let b = EditorModel(saver: EditorModelTests.FakeSaver()); b.session = ProjectSession(store: store)
        try b.load(data: Self.jpeg(0.7))
        a.edit { $0.exposure = 0.1 }                                       // touching a moves it to the top
        #expect(try store.all().first?.id == a.session?.project?.id)
    }
}
