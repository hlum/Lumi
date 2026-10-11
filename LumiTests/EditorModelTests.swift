import CoreImage
import Foundation
import Testing
@testable import Lumi

@MainActor
struct EditorModelTests {
    final class FakeSaver: PhotoSaving {
        var saved: [Data] = []
        var error: EditorError?
        func save(_ data: Data) async throws { if let error { throw error }; saved.append(data) }
    }

    static func model(_ saver: FakeSaver = FakeSaver(), size: CGFloat = 16) -> EditorModel {
        let m = EditorModel(saver: saver)
        m.load(image: RendererTests.solid(0.3, size: size))
        return m
    }

    @Test func noPreviewBeforeLoad() { #expect(EditorModel(saver: FakeSaver()).preview == nil) }

    @Test func loadGarbageThrows() {
        #expect(throws: EditorError.undecodable) { try EditorModel(saver: FakeSaver()).load(data: Data([1, 2, 3])) }
    }

    @Test func draftChangesPreviewButNotDocumentUntilCommit() {
        let m = Self.model()
        let base = RendererTests.pixel(m.preview!)[0]
        m.draftExposure = 1
        #expect(RendererTests.pixel(m.preview!)[0] > base)
        #expect(m.document.exposure == 0 && !m.canUndo)
        m.commitExposure()
        #expect(m.document.exposure == 1 && m.canUndo)
    }

    @Test func undoRestoresDraftAndRedoReapplies() {
        let m = Self.model()
        m.draftExposure = 1; m.commitExposure()
        m.undo(); #expect(m.draftExposure == 0 && m.document.exposure == 0)
        m.redo(); #expect(m.draftExposure == 1)
    }

    @Test func holdingCompareShowsOriginal() {
        let m = Self.model()
        let base = RendererTests.pixel(m.preview!)
        m.draftExposure = 1; m.commitExposure()
        m.showOriginal = true
        #expect(RendererTests.pixel(m.preview!) == base)
    }

    @Test func loadingResetsState() {
        let m = Self.model()
        m.draftExposure = 1; m.commitExposure()
        m.load(image: RendererTests.solid(0.5))
        #expect(!m.canUndo && m.draftExposure == 0 && m.document == EditDocument())
    }

    @Test func previewUsesProxyButExportUsesFullResolution() throws {
        let m = EditorModel(saver: FakeSaver())
        m.load(image: RendererTests.solid(0.3, size: 4096))
        #expect(max(m.preview!.extent.width, m.preview!.extent.height) <= EditorModel.proxySize + 1)
        #expect(m.original!.extent.width == 4096)
    }

    @Test func exportBeforeLoadThrows() {
        #expect(throws: EditorError.noImage) { try EditorModel(saver: FakeSaver()).exportData() }
    }

    @Test func exportIsFullSizeDecodableJPEG() throws {
        let m = Self.model(size: 64)
        m.draftExposure = 1; m.commitExposure()
        let img = try #require(CIImage(data: try m.exportData()))
        #expect(img.extent.width == 64 && img.extent.height == 64)
    }

    @Test func exportAppliesEdit() throws {
        let m = Self.model(size: 16)
        let before = RendererTests.pixel(try #require(CIImage(data: try m.exportData())))[0]
        m.draftExposure = 1; m.commitExposure()
        let after = RendererTests.pixel(try #require(CIImage(data: try m.exportData())))[0]
        #expect(after > before)
    }

    @Test func saveSendsDataToSaver() async {
        let s = FakeSaver(); let m = Self.model(s)
        await m.save()
        #expect(s.saved.count == 1 && m.didSave && m.saveError == nil)
    }

    @Test func saveFailureIsReported() async {
        let s = FakeSaver(); s.error = .photosDenied
        let m = Self.model(s)
        await m.save()
        #expect(!m.didSave && m.saveError == .photosDenied)
    }

    @Test func saveWithoutImageReportsNoImage() async {
        let m = EditorModel(saver: FakeSaver())
        await m.save()
        #expect(m.saveError == .noImage)
    }

    @Test func genericEditIsRecordedAndUndoable() {
        let m = Self.model()
        m.edit { $0.crop.flipH = true }
        #expect(m.document.crop.flipH && m.canUndo)
        m.edit { $0.adjust[.brightness] = 0.4 }
        m.undo(); #expect(m.draft.adjust.brightness == 0 && m.draft.crop.flipH)
        m.undo(); #expect(!m.draft.crop.flipH)
        m.redo(); m.redo()
        #expect(m.draft.adjust.brightness == 0.4)
    }

    @Test func uncommittedDraftShowsInPreviewButIsNotAnUndoStep() {
        let m = Self.model()
        let base = RendererTests.pixel(m.preview!)[0]
        m.draft.adjust[.brightness] = 0.8
        #expect(RendererTests.pixel(m.preview!)[0] > base && !m.canUndo)
        m.commit(); #expect(m.canUndo)
    }

    @Test func textLayerRendersIntoPreviewAndExport() throws {
        let m = Self.model(size: 200)
        let before = try #require(m.preview)
        m.edit { d in var s = d.layers; try? s.add(Layer(content: .text("MMMM", { var t = TextStyle(); t.size = 0.5; return t }()))); d.layers = s }
        #expect(m.document.layers.layers.count == 1)
        func lit(_ i: CIImage) -> Bool {
            var buf = [UInt8](repeating: 0, count: 4 * 200 * 200)
            RendererTests.ctx.render(i, toBitmap: &buf, rowBytes: 800, bounds: CGRect(x: 0, y: 0, width: 200, height: 200), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return buf.enumerated().contains { $0.offset % 4 == 0 && $0.element > 240 }
        }
        let after = try #require(m.preview)
        #expect(!lit(before) && lit(after))
        let exported = try #require(CIImage(data: try m.exportData()))
        #expect(exported.extent.width == 200)
    }

    @Test func emptyTextIsNotAdded() {
        let m = Self.model()
        m.edit { d in var s = d.layers; try? s.add(Layer(content: .text("  ", TextStyle()))); d.layers = s }
        #expect(m.document.layers.layers.isEmpty)
    }
}
