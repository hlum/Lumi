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

    // MARK: layer gestures
    static func modelWithText() -> EditorModel {
        let m = model(size: 100)
        m.edit { d in var s = d.layers; try? s.add(Layer(content: .text("Hi", TextStyle()))); d.layers = s }
        m.selectedLayer = m.draft.layers.layers[0].id
        return m
    }

    @Test func movingScalingAndRotatingTheSelectedLayer() {
        let m = Self.modelWithText()
        m.moveSelected(to: CGPoint(x: 0.25, y: 0.75))
        #expect(m.selectedLayerValue?.transform.center == CGPoint(x: 0.25, y: 0.75))
        m.scaleSelected(base: 1, by: 2); #expect(m.selectedLayerValue?.transform.scale == 2)
        m.scaleSelected(base: 2, by: 100); #expect(m.selectedLayerValue?.transform.scale == 20)              // clamped by the layer stack
        m.rotateSelected(base: 0.5, by: 0.25); #expect(m.selectedLayerValue?.transform.rotation == 0.75)
    }

    @Test func movesAreClampedToThePhoto() {
        let m = Self.modelWithText()
        m.moveSelected(to: CGPoint(x: -3, y: 9))
        #expect(m.selectedLayerValue?.transform.center == CGPoint(x: 0, y: 1))
    }

    @Test func aGestureIsOneUndoStep() {
        let m = Self.modelWithText()
        for i in 1...10 { m.moveSelected(to: CGPoint(x: 0.1 * Double(i), y: 0.5)) }                        // live drag, not committed
        let before = m.canUndo
        m.commit()
        m.undo()
        #expect(before && m.draft.layers.layers[0].transform.center == CGPoint(x: 0.5, y: 0.5))             // back to the start in a single undo
    }

    @Test func noSelectionMeansGesturesDoNothing() {
        let m = Self.modelWithText(); m.selectedLayer = nil
        m.moveSelected(to: CGPoint(x: 0.1, y: 0.1)); m.scaleSelected(base: 1, by: 3); m.rotateSelected(base: 0, by: 1); m.flipSelected()
        #expect(m.draft.layers.layers[0].transform == LayerTransform())
    }

    @Test func flipAndDeleteSelected() {
        let m = Self.modelWithText()
        m.flipSelected(); #expect(m.selectedLayerValue?.transform.flipH == true)
        m.deleteSelectedLayer(); #expect(m.draft.layers.layers.isEmpty && m.selectedLayer == nil)
    }

    @Test func movedTextLandsWhereTheTransformSays() throws {
        let m = EditorModelTests.model(size: 200)
        var st = TextStyle(); st.size = 0.3; st.color = RGBA(r: 1, g: 0, b: 0, a: 1)
        m.edit { d in var s = d.layers; try? s.add(Layer(content: .text("MM", st))); d.layers = s }
        m.selectedLayer = m.draft.layers.layers[0].id
        m.moveSelected(to: CGPoint(x: 0.2, y: 0.2)); m.commit()
        let out = try #require(m.preview)
        func redIn(_ r: CGRect) -> Bool { (Int(r.minX)..<Int(r.maxX)).contains { x in (Int(r.minY)..<Int(r.maxY)).contains { y in GeometryTests.rgb(out, x: x, y: y)[0] > 200 && GeometryTests.rgb(out, x: x, y: y)[1] < 80 } } }
        #expect(redIn(CGRect(x: 0, y: 120, width: 90, height: 80)))                                       // near the top-left (CI y is up)
        #expect(!redIn(CGRect(x: 110, y: 0, width: 90, height: 80)))                                      // nothing in the bottom-right
    }
}
