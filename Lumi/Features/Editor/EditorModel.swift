import CoreImage
import Observation
import Photos

protocol PhotoSaving {
    func save(_ data: Data) async throws
}

struct LibraryPhotoSaver: PhotoSaving {
    func save(_ data: Data) async throws {
        guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) != .denied else { throw EditorError.photosDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}

enum EditorError: Error, Equatable { case noImage, photosDenied, undecodable, exportFailed }

@Observable @MainActor
final class EditorModel {
    static let proxySize: CGFloat = 2048

    private(set) var original: CIImage?
    private var proxy: CIImage?
    private var stack = UndoStack(EditDocument())
    private let saver: PhotoSaving
    private let context = CIContext()

    /// Live slider value; committed to the document when the drag ends.
    var draftExposure: Double = 0
    var showOriginal = false
    private(set) var saveError: EditorError?
    private(set) var didSave = false

    init(saver: PhotoSaving = LibraryPhotoSaver()) { self.saver = saver }

    var document: EditDocument { stack.current }
    var canUndo: Bool { stack.canUndo }
    var canRedo: Bool { stack.canRedo }

    /// Image shown in the preview: proxy resolution, live exposure, or the untouched original while compare is held.
    var preview: CIImage? {
        guard let proxy else { return nil }
        if showOriginal { return proxy }
        var doc = document
        doc.exposure = draftExposure
        return Renderer.render(proxy, document: doc)
    }

    func load(data: Data) throws {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw EditorError.undecodable }
        load(image: img)
    }

    func load(image: CIImage) {
        original = image
        proxy = Renderer.proxy(image, maxDimension: Self.proxySize)
        stack = UndoStack(EditDocument())
        draftExposure = 0; showOriginal = false; didSave = false; saveError = nil
    }

    func commitExposure() {
        var doc = document
        doc.exposure = draftExposure
        stack.commit(doc)
    }

    func undo() { stack.undo(); draftExposure = document.exposure }
    func redo() { stack.redo(); draftExposure = document.exposure }

    /// Full-resolution render of the current document.
    func exportData() throws -> Data {
        guard let original else { throw EditorError.noImage }
        let out = Renderer.render(original, document: document)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(of: out, colorSpace: space) else { throw EditorError.exportFailed }
        return data
    }

    func save() async {
        do { try await saver.save(exportData()); didSave = true; saveError = nil }
        catch { saveError = error as? EditorError ?? .exportFailed; didSave = false }
    }
}
