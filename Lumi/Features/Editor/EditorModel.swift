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

    /// The document being edited live; `commit()` records it as an undo step.
    var draft = EditDocument()
    var draftExposure: Double {
        get { draft.exposure }
        set { draft.exposure = newValue }
    }
    var showOriginal = false
    var doodleBrush = DoodleStroke.Brush.solid
    var doodleColor = RGBA(r: 1, g: 0.3, b: 0.35, a: 1)
    /// Set while the remover tool is open so the preview can draw its brush gestures.
    var remover: RemoverModel?
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
        return Renderer.render(proxy, document: draft)
    }

    func load(data: Data) throws {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw EditorError.undecodable }
        load(image: img)
    }

    func load(image: CIImage) {
        original = image
        proxy = Renderer.proxy(image, maxDimension: Self.proxySize)
        stack = UndoStack(EditDocument())
        draft = EditDocument(); showOriginal = false; didSave = false; saveError = nil
    }

    func commit() { stack.commit(draft) }
    func commitExposure() { commit() }

    /// One-shot edit that is recorded immediately (buttons, toggles).
    func edit(_ change: (inout EditDocument) -> Void) { change(&draft); commit() }

    func undo() { stack.undo(); draft = stack.current }
    func redo() { stack.redo(); draft = stack.current }

    /// Full-resolution render of the current document.
    func exportData() throws -> Data {
        guard let original else { throw EditorError.noImage }
        let out = Renderer.render(original, document: draft)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw EditorError.exportFailed }
        // transparency needs PNG; JPEG would flatten it to black
        let keepsAlpha = draft.cutout?.background == .transparent
        guard let data = keepsAlpha ? context.pngRepresentation(of: out, format: .RGBA8, colorSpace: space)
                                    : context.jpegRepresentation(of: out, colorSpace: space) else { throw EditorError.exportFailed }
        return data
    }

    func save() async {
        do { try await saver.save(exportData()); didSave = true; saveError = nil }
        catch { saveError = error as? EditorError ?? .exportFailed; didSave = false }
    }
}
