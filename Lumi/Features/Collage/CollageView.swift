import PhotosUI
import SwiftUI

/// Collage: grid layouts (with border, shape, ratio, background), seamless and split looks, and freeform scrapbooking.
struct CollageView: View {
    enum Mode: String, CaseIterable { case grid = "Layout", seamless = "Seamless", freeform = "Freeform" }
    enum Tab: String, CaseIterable { case layout = "Layout", border = "Border", shape = "Shape", ratio = "Ratio", background = "Background" }
    @State private var items: [PhotosPickerItem] = []
    @State private var photos: [CIImage] = []
    @State private var mode = Mode.grid
    @State private var tab = Tab.layout
    @State private var state: CollageState?
    @State private var freeform = FreeformCollage()
    @State private var background = RGBA.white
    @State private var ratio: Double?
    @State private var selected: Int?
    @State private var drag: CGPoint?
    @State private var shown: CGImage?
    @State private var message: LocalizedStringKey?
    private let saver = LibraryPhotoSaver()
    static let backgrounds: [(name: String, color: RGBA)] = [("White", .white), ("Black", .black), ("Cream", RGBA(r: 0.99, g: 0.96, b: 0.88, a: 1)), ("Blush", RGBA(r: 0.98, g: 0.82, b: 0.85, a: 1)), ("Sky", RGBA(r: 0.7, g: 0.85, b: 0.98, a: 1)), ("Mint", RGBA(r: 0.8, g: 0.94, b: 0.88, a: 1))]
    static let ratios: [(String, Double?)] = [("Auto", nil), ("1:1", 1), ("3:4", 0.75), ("4:3", 4.0 / 3), ("9:16", 9.0 / 16)]

    var body: some View {
        ToolScaffold(title: "Collage", trailing: AnyView(HStack(spacing: 8) {
            PhotosPicker(selection: $items, maxSelectionCount: 9, matching: .images) { Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(LumiColor.text).frame(width: 44, height: 44).background(Circle().fill(LumiColor.surface)) }.accessibilityLabel("Add photos")
            LumiIconButton(symbol: "square.and.arrow.down", label: "Save", dark: true, disabled: shown == nil) { Task { await save() } }
        })) {
            canvas
        } panel: {
            if photos.count < 2 {
                PhotosPicker(selection: $items, maxSelectionCount: 9, matching: .images) { Label("Pick 2 to 9 photos", systemImage: "photo.on.rectangle").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.onAccent).background(Capsule().fill(LumiColor.accent)) }
            } else {
                LumiSegmented(items: Mode.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $mode, height: 40)
                if mode == .freeform { freeformControls } else { gridControls }
                if let message { Text(message).font(.footnote).foregroundStyle(LumiColor.textSecondary) }
            }
        }
        .onChange(of: items) { _, new in Task { await load(new) } }
        .onChange(of: mode) { _, _ in rebuild() }
    }

    // MARK: pieces

    @ViewBuilder private var canvas: some View {
        if let shown {
            GeometryReader { geo in
                let size = CGSize(width: shown.width, height: shown.height)
                let fit = min(geo.size.width / size.width, geo.size.height / size.height)
                let w = size.width * fit, h = size.height * fit
                Image(decorative: shown, scale: 1).resizable().frame(width: w, height: h).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .gesture(mode == .freeform ? freeformGesture(width: w, height: h) : nil)
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
        } else {
            VStack(spacing: 10) { Image(systemName: "square.grid.2x2").font(.system(size: 40)); Text("Pick 2 to 9 photos").font(LumiFont.headline()) }.foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var gridControls: some View {
        LumiCategoryTabs(items: Tab.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $tab)
        switch tab {
        case .layout:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    LumiChip(title: "Auto", symbol: "wand.and.stars") { autoLayout() }
                    ForEach(layouts) { l in LumiChip(title: LocalizedStringKey(l.name), selected: state?.layout.id == l.id) { state = CollageState(layout: mode == .seamless ? l.seamless : l, photoCount: photos.count); redraw() } }
                }
            }
        case .border:
            LumiSliderRow(title: "Border", value: Binding(get: { state?.border ?? 0 }, set: { state?.border = $0; redraw() }), range: 0...0.05, onEnd: {})
            LumiSliderRow(title: "Corners", value: Binding(get: { state?.cornerRadius ?? 0 }, set: { state?.cornerRadius = $0; redraw() }), range: 0...0.5, onEnd: {})
        case .shape:
            HStack(spacing: 8) {
                ForEach([CollageLayout.Shape.rect, .circle, .heart, .triangle], id: \.self) { s in
                    LumiChip(title: LocalizedStringKey(s.rawValue.capitalized), selected: state?.layout.slots.allSatisfy { $0.shape == s } == true) { state?.layout.slots = (state?.layout.slots ?? []).map { var x = $0; x.shape = s; return x }; redraw() }
                }
            }
        case .ratio:
            HStack(spacing: 8) { ForEach(Self.ratios, id: \.0) { r in LumiChip(title: LocalizedStringKey(r.0), selected: ratio == r.1) { ratio = r.1; autoLayout() } } }
        case .background:
            LumiSwatchRow(colors: Self.backgrounds, selected: background) { background = $0; redraw() }
        }
    }

    @ViewBuilder private var freeformControls: some View {
        HStack(spacing: 8) {
            LumiChip(title: "Shuffle", symbol: "shuffle") { shuffle() }
            LumiChip(title: "Front", symbol: "square.3.layers.3d.top.filled") { if let s = selected { freeform.bringToFront(s); selected = freeform.items.count - 1; redraw() } }.disabled(selected == nil)
            LumiChip(title: "Remove", symbol: "trash") { if let s = selected { freeform.remove(s); selected = nil; redraw() } }.disabled(selected == nil)
            Spacer()
        }
        LumiSwatchRow(colors: Self.backgrounds, selected: background) { background = $0; redraw() }
        Text("Drag a photo to move it, pinch to resize, twist to turn.").font(.footnote).foregroundStyle(LumiColor.textSecondary)
    }

    private func freeformGesture(width w: CGFloat, height h: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let p = CGPoint(x: v.location.x / w, y: v.location.y / h)
                if drag == nil { selected = freeform.item(at: CGPoint(x: v.startLocation.x / w, y: v.startLocation.y / h), photoAspects: photos.map { Double($0.extent.width / $0.extent.height) }); drag = p }
                if let s = selected { freeform.move(s, to: p); redraw() }
            }
            .onEnded { _ in drag = nil }
            .simultaneously(with: MagnifyGesture().onChanged { v in if let s = selected { freeform.scale(s, by: Double(v.velocity) > 0 ? 1.02 : 0.98); redraw() } })
    }

    // MARK: data

    private var layouts: [CollageLayout] {
        CollageLayout.builtin.filter { $0.slots.count == photos.count && (ratio == nil || abs($0.aspect - (ratio ?? 0)) < 0.01) }.prefix(24).map { $0 }
    }

    private func load(_ new: [PhotosPickerItem]) async {
        var imgs: [CIImage] = []
        for item in new { if let d = try? await item.loadTransferable(type: Data.self), let i = CIImage(data: d, options: [.applyOrientationProperty: true]) { imgs.append(i) } }
        photos = imgs
        rebuild()
    }

    private func rebuild() {
        guard photos.count >= 2 else { state = nil; shown = nil; return }
        if mode == .freeform {
            freeform = FreeformCollage(); freeform.aspect = 1
            for i in photos.indices { freeform.add(photo: i) }
            shuffle()
        } else { autoLayout() }
    }

    private func autoLayout() {
        guard photos.count >= 2 else { return }
        let pool = layouts.isEmpty ? CollageLayout.builtin : layouts
        guard let l = CollageLayout.autoPick(photoAspects: photos.map { Double($0.extent.width / $0.extent.height) }, from: pool) else { return }
        state = CollageState(layout: mode == .seamless ? l.seamless : l, photoCount: photos.count)
        redraw()
    }

    private func shuffle() {
        var rng = SystemRandomNumberGenerator()
        for i in freeform.items.indices {
            freeform.items[i].center = CGPoint(x: Double.random(in: 0.25...0.75, using: &rng), y: Double.random(in: 0.25...0.75, using: &rng))
            freeform.items[i].rotation = Double.random(in: -0.25...0.25, using: &rng); freeform.items[i].width = Double.random(in: 0.4...0.55, using: &rng)
        }
        redraw()
    }

    private func render(width: Int, proxy: Bool) -> CIImage? {
        let src = proxy ? photos.map { Renderer.proxy($0, maxDimension: 1200) } : photos
        if mode == .freeform { return FreeformRenderer.render(freeform, photos: src, width: width, background: background) }
        guard let s = state else { return nil }
        return CollageRenderer.render(s, photos: src, width: width, background: background)
    }

    private func redraw() {
        guard let img = render(width: 900, proxy: true) else { return }
        shown = CIContext().createCGImage(img, from: img.extent)
    }

    private func save() async {
        guard let img = render(width: 2400, proxy: false), let space = CGColorSpace(name: CGColorSpace.sRGB), let data = CIContext().jpegRepresentation(of: img, colorSpace: space) else { return }
        message = (try? await saver.save(data)) != nil ? "Saved to Photos" : "Couldn't save"
    }
}
