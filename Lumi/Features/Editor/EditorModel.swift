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

enum HairBrushMode: Hashable { case add, erase, fill }

@Observable @MainActor
final class EditorModel {
    static let proxySize: CGFloat = 2048

    private(set) var original: CIImage?
    private var proxy: CIImage?
    private var stack = UndoStack(EditDocument())
    private let saver: PhotoSaving
    /// When set, every committed edit is saved to this draft.
    var session: ProjectSession?
    private let context = CIContext()

    /// The document being edited live; `commit()` records it as an undo step.
    var draft = EditDocument()
    var draftExposure: Double {
        get { draft.exposure }
        set { draft.exposure = newValue }
    }
    var showOriginal = false
    var doodleBrush = DoodleStroke.Brush.solid
    var warpBrush = WarpBrush()
    var filterEraserActive = false
    var hairBrushActive = false
    var hairBrushMode = HairBrushMode.add
    /// The text or sticker layer the gestures act on.
    var selectedLayer: UUID?
    /// The eraser mask as of the last committed edit; a drag adds to it.
    var committedEraser: MaskCanvas? { stack.current.filterEraser }
    /// The last committed document (before the drag in progress).
    var stack0: EditDocument { stack.current }
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
        // upscaling is an export-time step: running a 4x model on the preview proxy would be slow and show no more than the screen can
        var live = draft; live.upscale = nil
        return Renderer.render(proxy, document: live)
    }

    func load(data: Data) throws {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw EditorError.undecodable }
        load(image: img)
        try session?.begin(original: data)
    }

    /// Reopens a saved draft: its original photo plus its edit list, with undo starting from the saved state.
    func openDraft() throws {
        guard let loaded = session?.load(), let img = CIImage(data: loaded.data, options: [.applyOrientationProperty: true]) else { throw EditorError.undecodable }
        load(image: img)
        stack = UndoStack(loaded.document); draft = loaded.document
    }

    func load(image: CIImage) {
        original = image
        proxy = Renderer.proxy(image, maxDimension: Self.proxySize)
        stack = UndoStack(EditDocument())
        draft = EditDocument(); showOriginal = false; didSave = false; saveError = nil
    }

    /// The enhance tool is offered only when the model is present and the photo is small enough to upscale.
    var canUpscale: Bool { Renderer.services.upscaler != nil && max(original?.extent.width ?? .infinity, original?.extent.height ?? .infinity) <= CGFloat(RealESRGANUpscaler.maxInputSide) }

    // MARK: layer gestures (live while dragging; `commit()` records one undo step when the gesture ends)

    private func updateSelected(_ change: (inout Layer) -> Void) {
        guard let id = selectedLayer else { return }
        var stack = draft.layers
        stack.update(id, change)
        draft.layers = stack
    }
    /// Moves the layer's center to a normalized point (0...1, top-left origin), clamped to the photo.
    func moveSelected(to p: CGPoint) { updateSelected { $0.transform.center = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1)) } }
    /// Multiplies the layer's scale (pinch); `base` is the scale when the gesture began.
    func scaleSelected(base: Double, by factor: Double) { updateSelected { $0.transform.scale = base * factor } }
    func rotateSelected(base: Double, by radians: Double) { updateSelected { $0.transform.rotation = base + radians } }
    func flipSelected() { updateSelected { $0.transform.flipH.toggle() }; commit() }
    func deleteSelectedLayer() {
        guard let id = selectedLayer else { return }
        var s = draft.layers; s.remove(id); draft.layers = s; selectedLayer = nil; commit()
    }
    var selectedLayerValue: Layer? { selectedLayer.flatMap { id in draft.layers.layers.first { $0.id == id } } }

    /// Cuts the main subject out of the photo and keeps it under "My stickers". Returns nil when no subject is found.
    @discardableResult
    func makeStickerFromSubject() -> CustomSticker? {
        guard let o = original, let masker = Renderer.services.subjectMasker, let mask = (try? masker.subjectMask(for: o)) ?? nil else { return nil }
        var c = CutoutConfig(); c.feather = 0.1
        return CustomStickerStore.shared.add(cutout: CutoutOps.apply(c, to: o, subjectMask: mask))
    }

    func commit() { stack.commit(draft); autosave() }

    /// Puts the document back to an earlier state (a tool's Cancel).
    func revert(to doc: EditDocument) { draft = doc; commit() }

    private func autosave() {
        guard let session else { return }
        session.save(stack.current, thumbnail: thumbnailData())
    }

    /// Small JPEG of the current look for the Projects grid.
    func thumbnailData(side: CGFloat = 256) -> Data? {
        guard let p = preview, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return context.jpegRepresentation(of: Renderer.proxy(p, maxDimension: side), colorSpace: space, options: [:])
    }
    func commitExposure() { commit() }

    /// One-shot edit that is recorded immediately (buttons, toggles).
    func edit(_ change: (inout EditDocument) -> Void) { change(&draft); commit() }

    func undo() { stack.undo(); draft = stack.current; autosave() }
    func redo() { stack.redo(); draft = stack.current; autosave() }

    var exportSettings = ExportSettings()

    /// Print preset: crops to the paper's aspect and exports at exact pixels for the DPI.
    func applyPrintSize(width: Double, height: Double, unit: LengthUnit, dpi: Double) {
        guard let o = original, width > 0, height > 0 else { return }
        let px = ExportSettings.printSize(width: width, height: height, unit: unit, dpi: dpi)
        edit { $0.crop.rect = CropSpec.rect(aspect: width, height, in: o.extent.size) }
        exportSettings.exactSize = px
    }
    /// Back to the photo's own size and framing.
    func clearPrintSize() { exportSettings.exactSize = nil; edit { $0.crop.rect = CGRect(x: 0, y: 0, width: 1, height: 1) } }
    /// Size the saved file will have, for the settings screen.
    var exportPixelSize: (w: Int, h: Int)? {
        guard let o = original else { return nil }
        let out = Renderer.render(o, document: draft).extent
        return exportSettings.fitted((Int(out.width), Int(out.height)))
    }
    /// Rough file size for the current settings.
    var estimatedBytes: Int? { exportPixelSize.map { exportSettings.estimatedBytes(width: $0.w, height: $0.h) } }

    /// Full-resolution render of the current document, encoded with `exportSettings`.
    func exportData() throws -> Data {
        guard let original else { throw EditorError.noImage }
        var out = Renderer.render(original, document: draft)
        let target = exportSettings.fitted((Int(out.extent.width), Int(out.extent.height)))
        if exportSettings.exactSize != nil {            // print size: scale to exactly these pixels (the crop already has this aspect)
            out = out.transformed(by: CGAffineTransform(scaleX: CGFloat(target.w) / out.extent.width, y: CGFloat(target.h) / out.extent.height))
                .transformed(by: CGAffineTransform(translationX: -out.extent.minX * CGFloat(target.w) / out.extent.width, y: -out.extent.minY * CGFloat(target.h) / out.extent.height))
        } else if target.w < Int(out.extent.width) {                       // downscale to the chosen maximum, never upscale
            let k = CGFloat(target.w) / out.extent.width
            out = out.transformed(by: CGAffineTransform(scaleX: k, y: k)).cropped(to: CGRect(x: out.extent.minX * k, y: out.extent.minY * k, width: CGFloat(target.w), height: CGFloat(target.h)))
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw EditorError.exportFailed }
        // transparency needs an alpha format: a transparent cutout is forced to PNG even if JPEG/HEIC was chosen
        let needsAlpha = draft.cutout?.background == .transparent
        let format: ImageFormat = needsAlpha && !exportSettings.format.supportsAlpha ? .png : exportSettings.format
        let q = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: exportSettings.quality]
        let data: Data?
        switch format {
        case .png: data = context.pngRepresentation(of: out, format: .RGBA8, colorSpace: space)
        case .jpeg: data = context.jpegRepresentation(of: out, colorSpace: space, options: q)
        case .heic: data = context.heifRepresentation(of: out, format: .RGBA8, colorSpace: space, options: q)
        }
        guard let data else { throw EditorError.exportFailed }
        return data
    }

    func save() async {
        do { try await saver.save(exportData()); didSave = true; saveError = nil }
        catch { saveError = error as? EditorError ?? .exportFailed; didSave = false }
    }
}
