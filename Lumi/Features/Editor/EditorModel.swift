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
    /// While the crop tool is open the preview shows the whole (rotated, straightened) picture and the overlay draws the crop rect.
    var cropEditing = false
    /// Width / height in pixels the crop rect is locked to; nil = free.
    var cropAspect: Double?
    /// Which part of the face the slider in use works on; the preview outlines it. Cleared shortly after the slider is released.
    var activeMark: FaceMark?
    var lightEraserActive = false
    /// The Remove tool's Clone tab is open, so painting on the photo clones instead of removing.
    var cloneActive = false
    /// Move preview: the picture as it looks now, played through a slow camera move.
    private(set) var motion: AnimatePhoto?
    private var motionFrame: CIImage?
    private var motionTask: Task<Void, Never>?
    /// Size of a tap-to-heal spot, as a fraction of the picture width.
    var blemishTapSize = 0.025
    /// Nails found in the picture (hand pose), for the Nails tool.
    private(set) var nailCount = 0
    /// Faces found in the picture as it looks before the face edit, for the outlines. Refreshed when a face tool opens.
    private(set) var overlayFaces: [FaceInfo] = []
    /// The hair mask as a tinted picture, so the Hair tool can show which pixels it will change.
    private(set) var hairOverlay: CGImage?
    private var markClear: Task<Void, Never>?
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
        if let motionFrame { return motionFrame }
        // upscaling is an export-time step: running a 4x model on the preview proxy would be slow and show no more than the screen can
        var live = draft; live.upscale = nil
        if cropEditing { live.crop.rect = CGRect(x: 0, y: 0, width: 1, height: 1) }
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
    var canUpscale: Bool { Renderer.services.upscaler != nil && RealESRGANUpscaler.isModelAvailable && max(original?.extent.width ?? .infinity, original?.extent.height ?? .infinity) <= CGFloat(RealESRGANUpscaler.maxInputSide) }

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

    /// Fixes colour in one tap: exposure, tonal range, cast and a little vibrance, from the picture's own statistics.
    func autoFix() {
        guard let proxy else { return }
        var base = draft; base.adjust = AdjustParams()
        let params = AutoFix.params(for: Renderer.render(Renderer.proxy(proxy, maxDimension: 256), document: base))
        edit { $0.adjust = params }
    }

    /// A small square crop of the photo before the filter step, for the filter tiles.
    func thumbnailSource() -> CIImage? {
        guard let proxy else { return nil }
        let small = Renderer.proxy(proxy, maxDimension: 160)
        let e = small.extent, s = min(e.width, e.height)
        return small.cropped(to: CGRect(x: e.midX - s / 2, y: e.midY - s / 2, width: s, height: s))
    }

    // MARK: move preview and GIF

    func startMotion(_ a: AnimatePhoto) {
        guard let proxy else { return }
        stopMotion()
        motion = a
        var live = draft; live.upscale = nil
        let base = Renderer.render(proxy, document: live)
        let mask: CIImage? = a.style == .parallax ? ((try? Renderer.services.subjectMasker?.subjectMask(for: base)) ?? nil) : nil
        motionTask = Task { [weak self] in
            let n = a.frameCount
            var i = 0
            while !Task.isCancelled {
                self?.motionFrame = a.frame(of: base, personMask: mask, at: n > 1 ? Double(i % n) / Double(n - 1) : 0)
                i += 1
                try? await Task.sleep(for: .milliseconds(Int(1000 / max(a.fps, 1))))
            }
        }
    }

    func stopMotion() { motionTask?.cancel(); motionTask = nil; motion = nil; motionFrame = nil }

    /// The current move as a looping GIF, saved to Photos.
    func saveMotionGIF() async -> Bool {
        guard let a = motion, let proxy else { return false }
        var live = draft; live.upscale = nil
        let base = Renderer.render(Renderer.proxy(proxy, maxDimension: 720), document: live)
        let mask: CIImage? = a.style == .parallax ? ((try? Renderer.services.subjectMasker?.subjectMask(for: base)) ?? nil) : nil
        let ctx = CIContext()
        let frames = a.frames(of: base, personMask: mask).compactMap { ctx.createCGImage($0, from: $0.extent) }
        guard let data = GIFMaker.encode(frames, options: .init(fps: a.fps, maxSide: 720, loopCount: 0)) else { return false }
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }; return true } catch { return false }
    }

    /// Shows or hides the outline for a slider; hiding waits a moment so the outline is still there when the finger lifts.
    func mark(_ m: FaceMark?, editing: Bool) {
        markClear?.cancel()
        if editing { activeMark = m; return }
        markClear = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled { self?.activeMark = nil }
        }
    }

    func refreshHairOverlay() {
        guard let proxy, let masker = Renderer.services.hairMasker else { hairOverlay = nil; return }
        var doc = draft; doc.hair = HairRetouch(); doc.upscale = nil
        let base = Renderer.render(Renderer.proxy(proxy, maxDimension: 640), document: doc)
        let h = draft.hair
        Task.detached { [base] in
            guard let m = (try? masker.hairMasks(in: base))?.first else { await MainActor.run { self.hairOverlay = nil }; return }
            let refined = HairMask.refine(m, add: h.add, remove: h.remove)
            let tint = CIImage(color: CIColor(red: 1, green: 0.48, blue: 0.27, alpha: 1)).cropped(to: refined.extent)
            let alpha = refined.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0.6, y: 0, z: 0, w: 0), "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
            let colored = tint.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: refined.extent), kCIInputMaskImageKey: alpha]).cropped(to: refined.extent)
            let cg = CIContext().createCGImage(colored, from: colored.extent)
            await MainActor.run { self.hairOverlay = cg }
        }
    }

    func refreshNailCount() {
        guard let proxy, let hands = Renderer.services.handFinder else { nailCount = 0; return }
        let img = proxy
        Task.detached {
            let n = NailRegions.find(in: img, finder: hands).count
            await MainActor.run { self.nailCount = n }
        }
    }

    /// Looks for faces in the picture without the face edit applied (landmarks should sit on the unretouched face).
    func refreshOverlayFaces() {
        guard let proxy, let finder = Renderer.services.faceLandmarker else { overlayFaces = []; return }
        var doc = draft; doc.face = FaceRetouch(); doc.upscale = nil
        let base = Renderer.render(proxy, document: doc)
        Task.detached { [base] in
            let faces = (try? finder.faces(in: base)) ?? []
            await MainActor.run { self.overlayFaces = faces }
        }
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
