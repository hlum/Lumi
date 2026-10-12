import PhotosUI
import SwiftUI
import UIKit
import VisionKit

// MARK: GIF maker

struct GIFMakerView: View {
    enum Loop: String, CaseIterable { case `repeat` = "Repeat", bounce = "Bounce", once = "Once" }
    enum Size: Int, CaseIterable { case small = 240, medium = 480, large = 720
        var title: LocalizedStringKey { switch self { case .small: "Small"; case .medium: "Medium"; case .large: "Large" } } }
    @State private var items: [PhotosPickerItem] = []
    @State private var frames: [CGImage] = []
    @State private var fps = 6.0
    @State private var loop = Loop.repeat
    @State private var size = Size.medium
    @State private var bytes: Int?
    @State private var message: LocalizedStringKey?

    private var ordered: [CGImage] { GIFMaker.sequence(frames, bounce: loop == .bounce) }

    var body: some View {
        ToolScaffold(title: "GIF maker", trailing: AnyView(PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) { Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(LumiColor.text).frame(width: 44, height: 44).background(Circle().fill(LumiColor.surface)) }.accessibilityLabel("Add photos"))) {
            if frames.isEmpty { VStack(spacing: 10) { Image(systemName: "film.stack").font(.system(size: 40)); Text("Pick 2 or more photos").font(LumiFont.headline()) }.foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else {
                TimelineView(.periodic(from: .now, by: 1 / max(fps, 1))) { ctx in
                    let seq = ordered
                    let i = seq.isEmpty ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate * fps) % seq.count
                    Image(decorative: seq[loop == .once ? min(i, seq.count - 1) : i], scale: 1).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: LumiShape.photo, style: .continuous))
                }
            }
        } panel: {
            if frames.count < 2 {
                PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) { Label("Choose photos", systemImage: "photo.on.rectangle").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.onAccent).background(Capsule().fill(LumiColor.accent)) }
            } else {
                LumiSliderRow(title: "Speed", value: $fps, range: 1...15, defaultValue: 6, unit: 1, onEnd: { Task { await estimate() } })
                HStack(spacing: 8) { ForEach(Loop.allCases, id: \.self) { l in LumiChip(title: LocalizedStringKey(l.rawValue), selected: loop == l) { loop = l; Task { await estimate() } } } }
                HStack(spacing: 8) { ForEach(Size.allCases, id: \.self) { s in LumiChip(title: s.title, selected: size == s) { size = s; Task { await estimate() } } } }
                if let bytes { Text("About \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))").font(.footnote).foregroundStyle(LumiColor.textSecondary) }
                LumiPrimaryButton(title: "Save GIF", symbol: "square.and.arrow.down") { Task { message = await save() ? "Saved to Photos" : "Couldn't save" } }
                if let message { Text(message).font(.footnote).foregroundStyle(LumiColor.textSecondary) }
            }
        }
        .onChange(of: items) { _, new in Task { await load(new) } }
    }

    private func load(_ new: [PhotosPickerItem]) async {
        var out: [CGImage] = []
        let ctx = CIContext()
        for it in new { if let d = try? await it.loadTransferable(type: Data.self), let i = CIImage(data: d, options: [.applyOrientationProperty: true]) {
            let p = Renderer.proxy(i, maxDimension: 720)
            if let cg = ctx.createCGImage(p, from: p.extent) { out.append(cg) }
        } }
        frames = out
        await estimate()
    }

    private func estimate() async {
        let seq = ordered, opts = GIFMaker.Options(fps: fps, maxSide: size.rawValue, loopCount: loop == .once ? 1 : 0)
        bytes = await Task.detached { GIFMaker.encode(seq, options: opts)?.count }.value
    }

    private func save() async -> Bool {
        guard let data = GIFMaker.encode(ordered, options: .init(fps: fps, maxSide: size.rawValue, loopCount: loop == .once ? 1 : 0)) else { return false }
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil) }; return true } catch { return false }
    }
}

// MARK: Stitch

struct StitchView: View {
    @State private var items: [PhotosPickerItem] = []
    @State private var images: [CIImage] = []
    @State private var vertical = true
    @State private var cut = true
    @State private var result: CIImage?
    @State private var message: LocalizedStringKey?

    var body: some View {
        ToolScaffold(title: "Stitch", trailing: AnyView(PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) { Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(LumiColor.text).frame(width: 44, height: 44).background(Circle().fill(LumiColor.surface)) }.accessibilityLabel("Add pictures"))) {
            CIImageFrame(image: result, placeholder: "Join screenshots or photos")
        } panel: {
            if images.count < 2 {
                PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) { Label("Choose pictures", systemImage: "photo.on.rectangle").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.onAccent).background(Capsule().fill(LumiColor.accent)) }
            } else {
                LumiSegmented(items: [(true, LocalizedStringKey("Top to bottom")), (false, LocalizedStringKey("Side by side"))], selection: $vertical, height: 40)
                LumiToggleRow(title: "Cut the repeated part", subtitle: "For screenshots that overlap", isOn: $cut)
                LumiPrimaryButton(title: "Save", symbol: "square.and.arrow.down") { Task { message = await save() ? "Saved to Photos" : "Couldn't save" } }
                if let message { Text(message).font(.footnote).foregroundStyle(LumiColor.textSecondary) }
            }
        }
        .onChange(of: items) { _, new in Task { await load(new) } }
        .onChange(of: vertical) { _, _ in rebuild() }
        .onChange(of: cut) { _, _ in rebuild() }
    }

    private func load(_ new: [PhotosPickerItem]) async {
        var out: [CIImage] = []
        for it in new { if let d = try? await it.loadTransferable(type: Data.self), let i = CIImage(data: d, options: [.applyOrientationProperty: true]) { out.append(i) } }
        images = out; rebuild()
    }

    private func rebuild() { result = Stitcher.stitch(images, direction: vertical ? .vertical : .horizontal, cutOverlap: cut) }

    private func save() async -> Bool {
        guard let result, let space = CGColorSpace(name: CGColorSpace.sRGB), let d = CIContext().jpegRepresentation(of: result, colorSpace: space) else { return false }
        return (try? await LibraryPhotoSaver().save(d)) != nil
    }
}

// MARK: Wallpaper

struct WallpaperView: View {
    @State private var item: PhotosPickerItem?
    @State private var source: CIImage?
    @State private var target = WallpaperMaker.targets[0]
    @State private var zoom = 1.0
    @State private var pan = CGPoint.zero
    @State private var message: LocalizedStringKey?
    @State private var dragStart: CGPoint?

    private var preview: CIImage? { source.map { WallpaperMaker.make($0, target: target, zoom: zoom, pan: pan) } }

    var body: some View {
        ToolScaffold(title: "Wallpaper", trailing: AnyView(PhotosPicker(selection: $item, matching: .images) { Image(systemName: "photo.badge.plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(LumiColor.text).frame(width: 44, height: 44).background(Circle().fill(LumiColor.surface)) }.accessibilityLabel("Choose photo"))) {
            CIImageFrame(image: preview, placeholder: "Pinch and drag to frame it")
                .gesture(DragGesture().onChanged { v in
                    if dragStart == nil { dragStart = pan }
                    let s = dragStart ?? .zero
                    pan = CGPoint(x: min(max(s.x - v.translation.width / 160, -1), 1), y: min(max(s.y - v.translation.height / 160, -1), 1))
                }.onEnded { _ in dragStart = nil })
        } panel: {
            if source == nil {
                PhotosPicker(selection: $item, matching: .images) { Label("Choose a photo", systemImage: "photo").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.onAccent).background(Capsule().fill(LumiColor.accent)) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(WallpaperMaker.targets, id: \.name) { t in LumiChip(title: LocalizedStringKey(t.name), selected: target == t) { target = t } } } }
                LumiSliderRow(title: "Zoom", value: Binding(get: { zoom - 1 }, set: { zoom = 1 + $0 * 3 }), range: 0...1, onEnd: {})
                LumiPrimaryButton(title: "Save wallpaper to Photos", symbol: "square.and.arrow.down") { Task { message = await save() ? "Saved to Photos" : "Couldn't save" } }
                if let message { Text(message).font(.footnote).foregroundStyle(LumiColor.textSecondary) }
            }
        }
        .onChange(of: item) { _, new in Task { if let d = try? await new?.loadTransferable(type: Data.self), let i = CIImage(data: d, options: [.applyOrientationProperty: true]) { source = i; zoom = 1; pan = .zero } } }
    }

    private func save() async -> Bool {
        guard let source, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        let out = WallpaperMaker.make(source, target: target, zoom: zoom, pan: pan)
        guard let d = CIContext().jpegRepresentation(of: out, colorSpace: space) else { return false }
        return (try? await LibraryPhotoSaver().save(d)) != nil
    }
}

// MARK: Scanner

struct ScannerView: View {
    @State private var items: [PhotosPickerItem] = []
    @State private var pages: [CIImage] = []
    @State private var index = 0
    @State private var filter = ScanFilter.enhance
    @State private var showCamera = false
    @State private var pdfURL: URL?
    @State private var message: LocalizedStringKey?

    private var current: CIImage? { pages.indices.contains(index) ? ScanTools.apply(filter, to: pages[index]) : nil }

    var body: some View {
        ToolScaffold(title: "Scan", trailing: AnyView(HStack(spacing: 8) {
            if VNDocumentCameraViewController.isSupported { LumiIconButton(symbol: "camera", label: "Scan with camera", raised: true) { showCamera = true } }
            PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) { Image(systemName: "photo.badge.plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(LumiColor.text).frame(width: 44, height: 44).background(Circle().fill(LumiColor.surface)) }.accessibilityLabel("Choose photos")
        })) {
            CIImageFrame(image: current, placeholder: "Scan a page or choose a photo of one")
        } panel: {
            if pages.isEmpty {
                PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) { Label("Choose photos of pages", systemImage: "doc.viewfinder").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.onAccent).background(Capsule().fill(LumiColor.accent)) }
            } else {
                if pages.count > 1 { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(pages.indices, id: \.self) { i in LumiChip(title: "Page \(i + 1)", selected: index == i) { index = i } } } } }
                HStack(spacing: 8) { ForEach(ScanFilter.allCases, id: \.self) { f in LumiChip(title: Self.title(f), selected: filter == f) { filter = f } } }
                HStack(spacing: 10) {
                    LumiPrimaryButton(title: "Copy text", symbol: "doc.on.doc") { copyText() }
                    if let pdfURL { ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "square.and.arrow.up").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.onSelectedPill).background(Capsule().fill(LumiColor.selectedPill)) } }
                    else { LumiPrimaryButton(title: "Make PDF", symbol: "doc.richtext") { makePDF() } }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(LumiColor.textSecondary) }
            }
        }
        .onChange(of: items) { _, new in Task { await load(new) } }
        .onChange(of: filter) { _, _ in pdfURL = nil }
        .sheet(isPresented: $showCamera) { DocumentCamera { imgs in pages += imgs.map { CIImage(image: $0) }.compactMap { $0 }; showCamera = false } }
    }

    private static func title(_ f: ScanFilter) -> LocalizedStringKey {
        switch f { case .original: "Original"; case .enhance: "Clean"; case .grayscale: "Gray"; case .blackWhite: "B&W" }
    }

    private func load(_ new: [PhotosPickerItem]) async {
        var out: [CIImage] = []
        for it in new { if let d = try? await it.loadTransferable(type: Data.self), let i = CIImage(data: d, options: [.applyOrientationProperty: true]) {
            // straighten the page when one is found
            if let r = ScanTools.detectPage(in: i) { out.append(ScanTools.flatten(i, topLeft: r.topLeft, topRight: r.topRight, bottomLeft: r.bottomLeft, bottomRight: r.bottomRight)) } else { out.append(i) }
        } }
        pages = out; index = 0; pdfURL = nil
    }

    private func copyText() {
        guard let c = current, let lines = try? ScanTools.recognizeText(in: c), !lines.isEmpty else { message = "No text found"; return }
        UIPasteboard.general.string = lines.joined(separator: "\n"); message = "Text copied"
    }

    private func makePDF() {
        let ctx = CIContext()
        let imgs = pages.compactMap { p -> UIImage? in let o = ScanTools.apply(filter, to: p); return ctx.createCGImage(o, from: o.extent).map { UIImage(cgImage: $0) } }
        guard let data = ScanTools.pdf(imgs) else { message = "Couldn't make the PDF"; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Scan-\(Int(Date().timeIntervalSince1970)).pdf")
        do { try data.write(to: url); pdfURL = url; message = "PDF ready" } catch { message = "Couldn't make the PDF" }
    }
}

private struct DocumentCamera: UIViewControllerRepresentable {
    var done: ([UIImage]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController { let v = VNDocumentCameraViewController(); v.delegate = context.coordinator; return v }
    func updateUIViewController(_ v: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) { done((0..<scan.pageCount).map { scan.imageOfPage(at: $0) }) }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { done([]) }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { done([]) }
    }
}
