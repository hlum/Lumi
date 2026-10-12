import PhotosUI
import SwiftData
import SwiftUI

enum EditorCategory: String, CaseIterable, Identifiable {
    case edit = "Edit", retouch = "Retouch", body = "Body", hair = "Hair", makeup = "Makeup"
    var id: String { rawValue }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case adjust = "Adjust", crop = "Crop", text = "Text", remove = "Remove", cutout = "Cutout", filter = "Filters", sticker = "Stickers", frame = "Frame", doodle = "Doodle", hair = "Hair", mosaic = "Mosaic", mark = "Mark", liquify = "Liquify", clean = "Clean", face = "Face", makeup = "Makeup", color = "Color", enhance = "Enhance", export = "Export"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .adjust: "slider.horizontal.3"; case .crop: "crop.rotate"; case .text: "textformat"; case .remove: "eraser"; case .cutout: "person.crop.rectangle"; case .filter: "camera.filters"; case .sticker: "face.smiling"; case .frame: "photo.artframe"; case .doodle: "scribble"; case .color: "paintpalette"; case .face: "face.smiling.inverse"; case .makeup: "wand.and.stars"; case .liquify: "hand.draw"; case .clean: "bandage"; case .mark: "checkmark.seal"; case .mosaic: "square.grid.3x3.fill"; case .hair: "comb"; case .enhance: "sparkles"; case .export: "square.and.arrow.up.on.square" }
    }
    var category: EditorCategory {
        switch self {
        case .face: .retouch
        case .liquify: .body
        case .hair: .hair
        case .makeup: .makeup
        default: .edit
        }
    }
    /// Tools shown in a category's grid, in order. Export is reached from Save.
    static func tools(in c: EditorCategory) -> [EditorTool] {
        switch c {
        case .edit: [.crop, .adjust, .filter, .color, .text, .sticker, .remove, .cutout, .clean, .enhance, .frame, .doodle, .mosaic, .mark]
        case .retouch: [.face, .clean]
        case .body: [.liquify]
        case .hair: [.hair]
        case .makeup: [.makeup]
        }
    }
}

struct EditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// Pass a project to reopen its draft.
    var project: Project?
    /// A photo chosen on the Home screen, and the tool to open on it.
    var initial: Data?
    var startTool: EditorTool?
    @State private var model = EditorModel()
    @State private var item: PhotosPickerItem?
    @State private var loadFailed = false
    @State private var tool: EditorTool?
    @State private var category = EditorCategory.edit
    @State private var snapshot: EditDocument?          // the document when the open tool began, for Cancel
    @State private var library = RecipeLibrary()
    @State private var recipeSaved = false
    @State private var showExport = false

    var body: some View {
        ZStack {
            LumiColor.ground.ignoresSafeArea()
            VStack(spacing: 12) {
                topBar
                if model.preview != nil { photo } else { empty }
                if model.preview != nil { bottom }
            }
        }
        .toolbar(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar)
        .task {
            let store = ProjectStore(context: context, directory: ProjectStore.defaultDirectory)
            model.session = ProjectSession(store: store, project: project)
            if project != nil { try? model.openDraft() }
            else if let initial, model.original == nil {
                if (try? model.load(data: initial)) == nil { loadFailed = true } else if let startTool { category = startTool.category; open(startTool) }
            }
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self), (try? model.load(data: data)) != nil { loadFailed = false }
                else { loadFailed = true }
            }
        }
        .sheet(isPresented: $showExport) { ExportPanel(model: model).padding().presentationDetents([.medium]) }
        .alert("Recipe saved", isPresented: $recipeSaved) {}
        .alert("Couldn't open that photo", isPresented: $loadFailed) {}
        .alert("Couldn't save", isPresented: .constant(model.saveError != nil)) {}
    }

    // MARK: pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            LumiIconButton(symbol: "xmark", label: "Close editor", raised: true) { dismiss() }
            Spacer()
            HStack(spacing: 0) {
                LumiIconButton(symbol: "arrow.uturn.backward", label: "Undo", disabled: !model.canUndo) { model.undo() }.background(.clear)
                LumiIconButton(symbol: "arrow.uturn.forward", label: "Redo", disabled: !model.canRedo) { model.redo() }
            }
            .background(Capsule().fill(LumiColor.surface)).shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            Spacer()
            Menu {
                Button("Save to Photos", systemImage: "square.and.arrow.down") { Task { await model.save() } }
                Button("Export options", systemImage: "slider.horizontal.3") { showExport = true }
                Button("Save as recipe", systemImage: "wand.and.stars.inverse") { saveRecipe() }.disabled(model.draft.operations.isEmpty)
                PhotosPicker("Change photo", selection: $item, matching: .images)
            } label: {
                Text("Save").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(LumiColor.onSelectedPill)
                    .padding(.horizontal, 20).frame(height: 44).background(Capsule().fill(LumiColor.selectedPill))
            }
            .disabled(model.original == nil)
        }
        .padding(.horizontal, 14).padding(.top, 4)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "photo").font(.system(size: 44)).foregroundStyle(LumiColor.textSecondary)
            Text("Pick a photo").font(LumiFont.title())
            PhotosPicker(selection: $item, matching: .images) {
                Text("Choose from library").font(LumiFont.chip()).foregroundStyle(LumiColor.onAccent).padding(.horizontal, 22).frame(height: 48).background(Capsule().fill(LumiColor.accent))
            }
            Spacer()
        }
    }

    private var photo: some View {
        let size = model.preview?.extent.size ?? CGSize(width: 1, height: 1)
        return MetalPreviewView(image: model.preview)
            .aspectRatio(max(size.width, 1) / max(size.height, 1), contentMode: .fit)
            .overlay { if tool == .text || tool == .sticker { LayerGestureOverlay(model: model) } }
            .overlay { if tool == .hair, model.hairBrushActive, let o = model.original { HairBrushOverlay(model: model, imageSize: o.extent.size) } }
            .overlay { if tool == .mosaic, let o = model.original { MosaicBrushOverlay(model: model, imageSize: o.extent.size) } }
            .overlay { if tool == .filter, model.filterEraserActive, let o = model.original { FilterEraserOverlay(model: model, imageSize: o.extent.size) } }
            .overlay { if tool == .face || tool == .makeup, let o = model.preview?.extent.size { FaceMarksOverlay(mark: model.activeMark, faces: model.overlayFaces, imageSize: o) } }
            .overlay { if tool == .crop, let size = model.preview?.extent.size { CropOverlay(model: model, imageSize: size) } }
            .overlay { if tool == .clean, let o = model.original { CleanBrushOverlay(model: model, imageSize: o.extent.size) } }
            .overlay { if tool == .liquify, let o = model.original { LiquifyOverlay(model: model, imageSize: o.extent.size) } }
            .overlay { if tool == .doodle, let o = model.original { DoodleOverlay(model: model, imageSize: o.extent.size) } }
            .overlay { if tool == .remove, let r = model.remover, let o = model.original { RemoverOverlay(remover: r, imageSize: o.extent.size) } }
            .overlay(alignment: .bottomTrailing) {
                Label("Compare", systemImage: "eye").font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 14).frame(height: 36).background(Capsule().fill(.white.opacity(0.9))).foregroundStyle(.black).padding(12)
                    .onLongPressGesture(minimumDuration: 0.1, pressing: { model.showOriginal = $0 }, perform: {})
                    .accessibilityLabel("Hold to compare with original")
            }
            .clipShape(RoundedRectangle(cornerRadius: LumiShape.photo, style: .continuous))
            .padding(.horizontal, LumiShape.margin)
    }

    @ViewBuilder private var bottom: some View {
        LumiPanel {
            VStack(spacing: 12) {
                if let t = tool {
                    LumiPanelHeader(title: LocalizedStringKey(t.rawValue), cancel: { close(revert: true) }, apply: { close(revert: false) })
                    ScrollView { panel(for: t).frame(maxWidth: .infinity) }.scrollBounceBehavior(.basedOnSize)
                } else {
                    grid
                }
            }
            .padding(.bottom, 8)
        }
        .frame(height: tool == nil ? 300 : 340)
    }

    private var grid: some View {
        let tools = EditorTool.tools(in: category)
        return VStack(spacing: 14) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 12) {
                    ForEach(tools) { t in
                        LumiToolCircle(symbol: t.symbol, value: nil, title: LocalizedStringKey(t.rawValue)) { open(t) }
                    }
                }
            }
            LumiSegmented(items: EditorCategory.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $category, height: 52)
        }
    }

    @ViewBuilder private func panel(for t: EditorTool) -> some View {
        switch t {
        case .adjust: AdjustPanel(model: model)
        case .crop: CropPanel(model: model)
        case .text: TextPanel(model: model)
        case .remove: RemoverPanel(editor: model)
        case .cutout: CutoutPanel(model: model)
        case .filter: FilterPanel(model: model)
        case .sticker: StickerPanel(model: model)
        case .frame: FramePanel(model: model)
        case .doodle: DoodlePanel(model: model)
        case .hair: HairPanel(model: model)
        case .mosaic: MosaicPanel(model: model)
        case .mark: MarkPanel(model: model)
        case .liquify: LiquifyPanel(model: model)
        case .clean: CleanPanel(model: model)
        case .face: FacePanel(model: model)
        case .makeup: FacePanel(model: model, only: [.looks, .makeup, .eyes])
        case .color: ColorPanel(model: model)
        case .enhance: EnhancePanel(model: model)
        case .export: ExportPanel(model: model)
        }
    }

    private func open(_ t: EditorTool) { snapshot = model.stack0; tool = t; model.cropEditing = (t == .crop); model.cropAspect = nil; if t == .face || t == .makeup { model.refreshOverlayFaces() } }
    private func close(revert: Bool) {
        if revert, let s = snapshot { model.revert(to: s) }
        model.filterEraserActive = false; model.hairBrushActive = false; model.cropEditing = false
        tool = nil; snapshot = nil
    }
}

extension EditorView {
    func saveRecipe() { if library.save(name: "", from: model.draft) != nil { recipeSaved = true } }
}

struct AdjustPanel: View {
    enum Group: String, CaseIterable {
        case light = "Light", color = "Color", detail = "Detail", finish = "Finish"
        var keys: [AdjustParams.Key] {
            switch self {
            case .light: [.exposure, .brightness, .contrast, .highlights, .shadows, .whites, .blacks]
            case .color: [.temperature, .tint, .vibrance, .saturation]
            case .detail: [.texture, .clarity, .dehaze, .sharpen]
            case .finish: [.vignette, .fade, .grain]
            }
        }
    }
    @Bindable var model: EditorModel
    @State private var group = Group.light
    @State private var key = AdjustParams.Key.exposure

    var body: some View {
        VStack(spacing: 12) {
            LumiSegmented(items: Group.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $group, height: 40)
                .onChange(of: group) { _, g in key = g.keys[0] }
            LumiSliderRow(title: LocalizedStringKey(key.rawValue.capitalized), value: Binding(get: { model.draft.adjust[key] }, set: { model.draft.adjust[key] = $0 }),
                          range: key.range, onEnd: { model.commit() })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group.keys, id: \.self) { k in
                        let v = Int((model.draft.adjust[k] * 100).rounded())
                        LumiToolCircle(symbol: nil, value: v == 0 ? "0" : (v > 0 && k.range.lowerBound < 0 ? "+\(v)" : "\(v)"), title: LocalizedStringKey(k.rawValue.capitalized), selected: k == key) { key = k }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AdjustParams.presets.keys.sorted(), id: \.self) { name in
                        LumiChip(title: LocalizedStringKey(name.capitalized)) { model.edit { $0.adjust = AdjustParams.presets[name]! } }
                    }
                    LumiChip(title: "Reset all", symbol: "arrow.counterclockwise") { model.edit { $0.adjust = AdjustParams() } }
                }
            }
        }
    }
}

struct CropPanel: View {
    @Bindable var model: EditorModel
    @State private var group = Group.ratio
    @State private var ratio = "Free"
    enum Group: String, CaseIterable { case ratio = "Ratio", straighten = "Straighten", flip = "Rotate" }
    static let presets: [(String, Double, Double)] = [("Free", 0, 0), ("Original", -1, -1), ("1:1", 1, 1), ("4:5 Post", 4, 5), ("3:4", 3, 4), ("9:16 Story", 9, 16), ("16:9", 16, 9), ("3:2", 3, 2), ("2:3", 2, 3), ("5:7", 5, 7)]

    var body: some View {
        VStack(spacing: 12) {
            LumiSegmented(items: Group.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $group, height: 40)
            switch group {
            case .ratio:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(Self.presets, id: \.0) { p in LumiChip(title: LocalizedStringKey(p.0), selected: ratio == p.0) { pick(p) } } }
                }
            case .straighten:
                LumiSliderRow(title: "Straighten", value: Binding(get: { model.draft.crop.angle }, set: { model.draft.crop.angle = $0 }), range: -45...45, unit: 1, onEnd: { resetRect(); model.commit() })
                LumiSliderRow(title: "Vertical", value: Binding(get: { model.draft.crop.keystoneV }, set: { model.draft.crop.keystoneV = $0 }), range: -1...1, onEnd: { model.commit() })
                LumiSliderRow(title: "Horizontal", value: Binding(get: { model.draft.crop.keystoneH }, set: { model.draft.crop.keystoneH = $0 }), range: -1...1, onEnd: { model.commit() })
                LumiChip(title: "Auto level", symbol: "level") {
                    if let o = model.original, let a = AutoStraighten.angle(for: Renderer.proxy(o, maxDimension: 1024)) { model.edit { $0.crop.angle = a }; resetRect(); model.commit() }
                }
            case .flip:
                HStack(spacing: 8) {
                    LumiChip(title: "Rotate", symbol: "rotate.right") { model.edit { $0.crop.quarterTurns = ($0.crop.quarterTurns + 1) % 4; $0.crop.rect = CGRect(x: 0, y: 0, width: 1, height: 1) }; ratio = "Free"; model.cropAspect = nil }
                    LumiChip(title: "Flip", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right") { model.edit { $0.crop.flipH.toggle() } }
                    LumiChip(title: "Flip V", symbol: "arrow.up.and.down.righttriangle.up.righttriangle.down") { model.edit { $0.crop.flipV.toggle() } }
                    LumiChip(title: "Reset", symbol: "arrow.counterclockwise") { model.edit { $0.crop = CropSpec() }; ratio = "Free"; model.cropAspect = nil }
                }
            }
        }
    }

    private func resetRect() { model.draft.crop.rect = CGRect(x: 0, y: 0, width: 1, height: 1); ratio = "Free"; model.cropAspect = nil }

    private func pick(_ p: (String, Double, Double)) {
        ratio = p.0
        guard let size = model.preview?.extent.size else { return }
        if p.1 == 0 { model.cropAspect = nil; return }
        let aspect = p.1 < 0 ? Double(size.width / size.height) : p.1 / p.2
        model.cropAspect = aspect
        model.edit { $0.crop.rect = CropSpec.rect(aspect: aspect, 1, in: size) }
    }
}

/// The crop frame over the picture: thirds, dimmed outside, drag corners, edges or the inside.
struct CropOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    @State private var active: CropMath.Handle?
    @State private var start = CGRect.zero

    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            let d = map.displayed
            let r = model.draft.crop.rect
            let view = CGRect(x: d.minX + r.minX * d.width, y: d.minY + r.minY * d.height, width: r.width * d.width, height: r.height * d.height)
            ZStack {
                Path { p in p.addRect(CGRect(origin: .zero, size: geo.size)); p.addRect(view) }.fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
                Path { p in
                    for i in 1...2 {
                        let f = CGFloat(i) / 3
                        p.move(to: CGPoint(x: view.minX + view.width * f, y: view.minY)); p.addLine(to: CGPoint(x: view.minX + view.width * f, y: view.maxY))
                        p.move(to: CGPoint(x: view.minX, y: view.minY + view.height * f)); p.addLine(to: CGPoint(x: view.maxX, y: view.minY + view.height * f))
                    }
                }.stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                Rectangle().path(in: view).stroke(Color.white, lineWidth: 1.5)
                ForEach(Array([view.origin, CGPoint(x: view.maxX, y: view.minY), CGPoint(x: view.minX, y: view.maxY), CGPoint(x: view.maxX, y: view.maxY)].enumerated()), id: \.offset) { _, c in
                    Circle().fill(Color.white).frame(width: 18, height: 18).shadow(radius: 2).position(c)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if active == nil {
                        // touch point in normalized picture space
                        let p = CGPoint(x: (v.startLocation.x - d.minX) / max(d.width, 1), y: (v.startLocation.y - d.minY) / max(d.height, 1))
                        active = CropMath.handle(at: p, in: model.draft.crop.rect, slop: 28 / max(min(d.width, d.height), 1))
                        start = model.draft.crop.rect
                    }
                    guard let h = active else { return }
                    let delta = CGPoint(x: v.translation.width / max(d.width, 1), y: v.translation.height / max(d.height, 1))
                    model.draft.crop.rect = CropMath.drag(start, handle: h, by: delta, aspect: model.cropAspect, imageSize: imageSize)
                }
                .onEnded { _ in active = nil; model.commit() })
        }
    }
}

struct TextPanel: View {
    @Bindable var model: EditorModel
    @State private var text = ""
    @State private var font = FontLibrary.all.first!.postScript
    @State private var preset: TextPreset?
    @State private var behind = false

    var body: some View {
        VStack {
            Picker("Font", selection: $font) { ForEach(FontLibrary.all) { Text($0.name).tag($0.postScript) } }.pickerStyle(.menu)
            HStack {
                TextField("Add text", text: $text).textFieldStyle(.roundedBorder)
                Button("Add") {
                    var style = preset?.style ?? TextStyle(); style.fontName = font
                    var layer = Layer(content: .text(text, style)); layer.behindSubject = behind
                    model.edit { d in var s = d.layers; try? s.add(layer); d.layers = s }; model.selectedLayer = layer.id   // the stack rejects empty text
                    text = ""
                }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(TextStylePresets.all) { p in
                        Button(LocalizedStringKey(p.name)) { font = p.style.fontName; preset = p }.buttonStyle(LumiButtonStyle()).lumiSelected(preset == p)
                    }
                }.padding(.horizontal)
            }
            Toggle("Behind subject", isOn: $behind).padding(.horizontal)
            VStack(spacing: 6) {
                ForEach(model.draft.layers.layers) { l in
                    if case .text(let str, _) = l.content {
                        HStack {
                            Text(str).font(LumiFont.chip()).fontWeight(model.selectedLayer == l.id ? .heavy : .regular).onTapGesture { model.selectedLayer = l.id }
                            Spacer()
                            Menu("Style") { ForEach(TextStylePresets.all) { p in Button(LocalizedStringKey(p.name)) { let id = l.id; model.edit { d in var st = d.layers; st.update(id) { $0 = TextStylePresets.apply(p, to: $0) }; d.layers = st } } } }
                            Button("Delete", systemImage: "trash", role: .destructive) { let id = l.id; model.edit { d in var st = d.layers; st.remove(id); d.layers = st } }.labelStyle(.iconOnly)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 44).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LumiColor.well))
                    }
                }
            }
        }
    }
}

struct RemoverOverlay: View {
    let remover: RemoverModel
    let imageSize: CGSize
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            if let overlay = remover.mask.tintedImage() {
                Image(decorative: overlay, scale: 1).resizable().frame(width: map.displayed.width, height: map.displayed.height)
                    .position(x: map.displayed.midX, y: map.displayed.midY).allowsHitTesting(false)
            }
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = map.toImageClamped(v.location)
                        if isDragging { remover.move(to: p) } else { isDragging = true; remover.begin(at: p) }
                    }
                    .onEnded { v in remover.end(at: map.toImageClamped(v.location)); isDragging = false })
        }
    }
}

struct CutoutPanel: View {
    @Bindable var model: EditorModel
    private var config: CutoutConfig { model.draft.cutout ?? CutoutConfig() }
    private let choices: [(String, CutoutConfig.Background)] = [
        ("Clear", .transparent), ("White", .color(.white)), ("Black", .color(.black)),
        ("Sky", .gradient(RGBA(r: 0.55, g: 0.75, b: 1, a: 1), .white)), ("Blur", .blur(0.5)),
    ]

    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Off") { model.edit { $0.cutout = nil } }.buttonStyle(LumiButtonStyle())
                    ForEach(choices, id: \.0) { name, bg in
                        Button(name) { model.edit { var c = $0.cutout ?? CutoutConfig(); c.background = bg; $0.cutout = c } }.buttonStyle(LumiButtonStyle())
                    }
                }.padding(.horizontal)
            }
            Button("Save as sticker", systemImage: "face.smiling") { model.makeStickerFromSubject() }.buttonStyle(LumiButtonStyle())
            slider("Soft edge", \.feather, 0...1)
            slider("Edge shift", \.shift, -1...1)
        }
    }

    private func slider(_ title: String, _ path: WritableKeyPath<CutoutConfig, Double>, _ range: ClosedRange<Double>) -> some View {
        LumiSliderRow(title: LocalizedStringKey(title), value: Binding(get: { config[keyPath: path] }, set: { v in var c = config; c[keyPath: path] = v; model.draft.cutout = c }), range: range, onEnd: { model.commit() }).disabled(model.draft.cutout == nil)
    }
}

struct FilterPanel: View {
    @Bindable var model: EditorModel
    @State private var category = FilterLibrary.shared.categories.first ?? ""
    @State private var prefs = FilterPrefsBox()
    @State private var erasing = false
    private let library = FilterLibrary.shared
    private let favorites = "★"

    private var shown: [FilterEntry] {
        if category == favorites { return prefs.prefs.favorites.compactMap { library.entry($0) } }
        if category == "Recent" { return prefs.prefs.recents.compactMap { library.entry($0) } }
        return library.entries(in: category).filter { !prefs.prefs.hidden.contains($0.id) }
    }

    var body: some View {
        VStack {
            HStack {
                Picker("Category", selection: $category) {
                    Text("★ Favorites").tag(favorites); Text("Recent").tag("Recent")
                    ForEach(library.categories, id: \.self) { Text($0.capitalized).tag($0) }
                }.pickerStyle(.menu)
                if let id = model.draft.filter?.id {
                    Button(prefs.isFavorite(id) ? "Unfavorite" : "Favorite", systemImage: prefs.isFavorite(id) ? "star.fill" : "star") { prefs.toggleFavorite(id) }.labelStyle(.iconOnly)
                }
                Toggle("Eraser", isOn: $erasing).fixedSize().disabled(model.draft.filter == nil)
            }.padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Off") { model.edit { $0.filter = nil; $0.filterEraser = nil } }.buttonStyle(LumiButtonStyle())
                    ForEach(shown) { e in
                        Button(LocalizedStringKey(e.name)) { prefs.used(e.id); let keep = model.draft.filter?.intensity ?? 1; model.edit { $0.filter = (e.id, keep) } }
                            .buttonStyle(LumiButtonStyle()).lumiSelected(model.draft.filter?.id == e.id)
                    }
                }.padding(.horizontal)
            }
            if erasing {
                HStack {
                    Text("Paint where the filter should go away").font(.caption).foregroundStyle(.secondary)
                    Button("Clear eraser") { model.edit { $0.filterEraser = nil } }.buttonStyle(LumiButtonStyle())
                }
            }
            LumiSliderRow(title: "Intensity", value: Binding(get: { model.draft.filter?.intensity ?? 1 }, set: { v in if let f = model.draft.filter { model.draft.filter = (f.id, v) } }), range: 0...1, defaultValue: 1, onEnd: { model.commit() })
                .disabled(model.draft.filter == nil).opacity(model.draft.filter == nil ? 0.5 : 1)
        }
        .onChange(of: erasing) { _, on in model.filterEraserActive = on }
        .onDisappear { model.filterEraserActive = false }
    }
}

struct StickerPanel: View {
    @Bindable var model: EditorModel
    @State private var query = ""
    @State private var outline = 0.0
    @State private var noSubject = false

    var body: some View {
        VStack {
            TextField("Search", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal)
            HStack {
                Button("Make from subject", systemImage: "person.crop.circle.badge.plus") { if model.makeStickerFromSubject() == nil { noSubject = true } }.buttonStyle(LumiButtonStyle())
                ForEach(CustomStickerStore.shared.items) { c in
                    Button { add(c.id) } label: {
                        if let ci = CustomStickerStore.shared.image(c.id), let cg = CIContext().createCGImage(Renderer.proxy(ci, maxDimension: 96), from: Renderer.proxy(ci, maxDimension: 96).extent) { Image(decorative: cg, scale: 1).resizable().scaledToFit().frame(width: 44, height: 44) } else { Text(c.name) }
                    }.contextMenu { Button("Delete", role: .destructive) { CustomStickerStore.shared.remove(c.id) } }
                }
            }.padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(StickerLibrary.search(query)) { s in
                        Button { add(s.id) } label: {
                            if let ci = StickerLibrary.image(s.id, side: 96), let cg = CIContext().createCGImage(ci, from: ci.extent) {
                                Image(decorative: cg, scale: 1).resizable().frame(width: 44, height: 44)
                            } else { Text(s.name) }
                        }
                        .accessibilityLabel(s.name)
                    }
                }.padding(.horizontal)
            }
            LumiSliderRow(title: "Outline", value: $outline, range: 0...0.05, onEnd: { model.commit() })
        }
    }

    private func add(_ id: String) {
        let layer = Layer(content: .sticker(id: id, outline: outline))
        model.edit { d in var s = d.layers; try? s.add(layer); d.layers = s }; model.selectedLayer = layer.id
    }
}

struct FramePanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack {
            Picker("Style", selection: Binding(get: { model.draft.frame.style }, set: { v in model.edit { var f = $0.frame; f.style = v; if f.padding == 0 { f.padding = 0.04 }; $0.frame = f } })) {
                ForEach(FrameConfig.Style.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal)
            LumiSliderRow(title: "Padding", value: Binding(get: { model.draft.frame.padding }, set: { model.draft.frame.padding = $0 }), range: 0...0.25, onEnd: { model.commit() })
            HStack {
                ForEach([("White", RGBA.white), ("Black", RGBA.black), ("Cream", RGBA(r: 1, g: 0.95, b: 0.8, a: 1))], id: \.0) { name, c in
                    Button(name) { model.edit { var f = $0.frame; f.color = c; $0.frame = f } }.buttonStyle(LumiButtonStyle())
                }
            }
        }
    }
}

struct DoodlePanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack {
            Picker("Brush", selection: Bindable(model).doodleBrush) { ForEach(DoodleStroke.Brush.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }.pickerStyle(.menu)
            HStack {
                ForEach([("Red", RGBA(r: 1, g: 0.3, b: 0.35, a: 1)), ("Yellow", RGBA(r: 1, g: 0.85, b: 0.2, a: 1)), ("Blue", RGBA(r: 0.3, g: 0.6, b: 1, a: 1)), ("White", RGBA.white)], id: \.0) { n, c in
                    Button(n) { model.doodleColor = c }.buttonStyle(LumiButtonStyle())
                }
            }
            Button("Undo stroke", systemImage: "arrow.uturn.backward") { model.edit { $0.doodle = Array($0.doodle.dropLast()) } }.labelStyle(.iconOnly).disabled(model.draft.doodle.isEmpty)
        }
    }
}

struct DoodleOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    @State private var points: [CGPoint] = []
    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in let p = map.toImageClamped(v.location); points.append(CGPoint(x: p.x / imageSize.width, y: p.y / imageSize.height)) }
                .onEnded { _ in
                    let stroke = DoodleStroke(brush: model.doodleBrush, points: Doodle.snappedToLine(points), color: model.doodleColor)
                    model.edit { $0.doodle = $0.doodle + [stroke] }; points = []
                })
        }
    }
}

struct EnhancePanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 12) {
            if model.canUpscale {
                Text("Sharper, bigger photo. Applied when you save.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Off") { model.edit { $0.upscale = nil } }.buttonStyle(LumiButtonStyle())
                    Button("2×") { model.edit { $0.upscale = 2 } }.buttonStyle(LumiButtonStyle()).lumiSelected(model.draft.upscale == 2)
                    Button("4×") { model.edit { $0.upscale = 4 } }.buttonStyle(LumiButtonStyle()).lumiSelected(model.draft.upscale == 4)
                }
            } else {
                Text("Enhance works on photos up to 2048 px on the long side.").font(.caption).foregroundStyle(.secondary).padding()
            }
            if Renderer.services.colorizer != nil, let o = model.original, max(o.extent.width, o.extent.height) <= CGFloat(SiggraphColorizer.maxInputSide) {
                HStack {
                    Text("Colorize").font(.caption)
                    Button("Off") { model.edit { $0.colorize = nil } }.buttonStyle(LumiButtonStyle())
                    Button("50%") { model.edit { $0.colorize = 0.5 } }.buttonStyle(LumiButtonStyle())
                    Button("100%") { model.edit { $0.colorize = 1 } }.buttonStyle(LumiButtonStyle())
                }
            }
            if let o = model.original {
                Button("Restore old photo", systemImage: "wand.and.stars") {
                    let plan = OldPhotoRestore.plan(for: o, canUpscale: model.canUpscale, canColorize: Renderer.services.colorizer != nil)
                    model.edit { $0 = OldPhotoRestore.apply(plan, to: $0) }
                }.buttonStyle(LumiButtonStyle(prominent: true))
            }
        }
    }
}

struct ExportPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 10) {
            Picker("Format", selection: $model.exportSettings.format) { ForEach(ImageFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) } }.pickerStyle(.segmented).padding(.horizontal)
            if model.exportSettings.format != .png {
                LumiSliderRow(title: "Quality", value: $model.exportSettings.quality, range: 0.3...1, onEnd: { model.commit() })
            }
            Picker("Max size", selection: Binding(get: { model.exportSettings.maxLongSide ?? 0 }, set: { model.exportSettings.maxLongSide = $0 == 0 ? nil : $0 })) {
                Text("Original").tag(0); Text("4096").tag(4096); Text("2048").tag(2048); Text("1080").tag(1080)
            }.pickerStyle(.segmented).padding(.horizontal)
            HStack {
                Text("Print").font(.caption)
                Button("10×15 cm") { model.applyPrintSize(width: 10, height: 15, unit: .cm, dpi: 300) }.buttonStyle(LumiButtonStyle())
                Button("A4") { model.applyPrintSize(width: 210, height: 297, unit: .mm, dpi: 300) }.buttonStyle(LumiButtonStyle())
                Button("Off") { model.clearPrintSize() }.buttonStyle(LumiButtonStyle())
            }
            if let s = model.exportPixelSize, let b = model.estimatedBytes {
                Text("\(s.w) × \(s.h) px · about \(ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ColorPanel: View {
    enum Section: String, CaseIterable { case hsl = "HSL", curves = "Curves", tone = "Tone", palette = "Palette" }
    enum Channel: String, CaseIterable { case rgb = "RGB", red = "R", green = "G", blue = "B" }
    @Bindable var model: EditorModel
    @State private var section = Section.hsl
    @State private var band = 0
    @State private var channel = Channel.rgb
    @State private var shadows = 0.0
    @State private var mids = 0.0
    @State private var highs = 0.0

    var body: some View {
        VStack(spacing: 6) {
            Picker("Section", selection: $section) { ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal)
            switch section {
            case .hsl:
                Picker("Band", selection: $band) { ForEach(0..<8, id: \.self) { Text(ColorGrade.bandNames[$0]).tag($0) } }.pickerStyle(.menu)
                slider("Hue", Binding(get: { model.draft.grade.bands[band].hue }, set: { model.draft.grade.bands[band].hue = $0 }))
                slider("Saturation", Binding(get: { model.draft.grade.bands[band].sat }, set: { model.draft.grade.bands[band].sat = $0 }))
                slider("Luminance", Binding(get: { model.draft.grade.bands[band].lum }, set: { model.draft.grade.bands[band].lum = $0 }))
            case .curves:
                Picker("Channel", selection: $channel) { ForEach(Channel.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(ColorGrade.curvePresets.keys.sorted(), id: \.self) { name in
                            Button(name.capitalized) { let c = ColorGrade.curvePresets[name]!; model.edit { $0.grade.rgbCurve = c.rgb; $0.grade.redCurve = c.r; $0.grade.greenCurve = c.g; $0.grade.blueCurve = c.b } }.buttonStyle(LumiButtonStyle())
                        }
                        Button("Reset") { model.edit { $0.grade.rgbCurve = ToneCurve(); $0.grade.redCurve = ToneCurve(); $0.grade.greenCurve = ToneCurve(); $0.grade.blueCurve = ToneCurve() }; shadows = 0; mids = 0; highs = 0 }.buttonStyle(LumiButtonStyle())
                    }.padding(.horizontal)
                }
                slider("Shadows", $shadows, apply: curve); slider("Midtones", $mids, apply: curve); slider("Highlights", $highs, apply: curve)
            case .tone:
                slider("Shadow tint", Binding(get: { model.draft.grade.shadows.sat }, set: { model.draft.grade.shadows.sat = $0 }), range: 0...1)
                slider("Shadow hue", Binding(get: { model.draft.grade.shadows.hue / 360 }, set: { model.draft.grade.shadows.hue = $0 * 360 }), range: 0...1)
                slider("Highlight tint", Binding(get: { model.draft.grade.highlights.sat }, set: { model.draft.grade.highlights.sat = $0 }), range: 0...1)
                slider("Highlight hue", Binding(get: { model.draft.grade.highlights.hue / 360 }, set: { model.draft.grade.highlights.hue = $0 * 360 }), range: 0...1)
                Stepper("Posterize: \(model.draft.grade.posterize == 0 ? "off" : "\(model.draft.grade.posterize)")", value: Binding(get: { model.draft.grade.posterize }, set: { v in model.edit { $0.grade.posterize = v == 1 ? 0 : v } }), in: 0...16).padding(.horizontal)
            case .palette:
                if let o = model.original {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(Array(ColorSampler.palette(Renderer.proxy(o, maxDimension: 256), count: 8).enumerated()), id: \.offset) { _, c in
                            Circle().fill(Color(red: c.r, green: c.g, blue: c.b)).frame(width: 36, height: 36).overlay(Circle().stroke(.secondary, lineWidth: 1))
                        } }.padding(.horizontal)
                    }
                    Text("Colors in this photo").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func curve() {
        let c = ColorGrade.curve(shadows: shadows, mids: mids, highlights: highs)
        switch channel {
        case .rgb: model.draft.grade.rgbCurve = c
        case .red: model.draft.grade.redCurve = c
        case .green: model.draft.grade.greenCurve = c
        case .blue: model.draft.grade.blueCurve = c
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, range: ClosedRange<Double> = -1...1, apply: (() -> Void)? = nil) -> some View {
        LumiSliderRow(title: LocalizedStringKey(title), value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; apply?() }), range: range, onEnd: { model.commit() })
    }
}

struct FacePanel: View {
    enum Group: String, CaseIterable { case looks = "Looks", ratio = "Ratio", skin = "Skin", shape = "Shape", makeup = "Makeup", eyes = "Eyes", detail = "Detail" }
    @Bindable var model: EditorModel
    var only: [Group] = Group.allCases
    @State private var group = Group.looks
    @State private var strength = 1.0
    @State private var lookID = AutoBeauty.looks[0].id
    @State private var reference: PhotosPickerItem?
    @State private var referenceFailed = false

    var body: some View {
        content
            .onChange(of: reference) { _, new in Task { await recreate(new) } }
            .alert("Couldn't read a face", isPresented: $referenceFailed) {}
    }

    private var content: some View {
        VStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(only, id: \.self) { g in LumiChip(title: LocalizedStringKey(g.rawValue), selected: group == g) { group = g } } }
            }
            ScrollView {
                VStack(spacing: 8) {
                    switch group {
                    case .looks:
                        HStack {
                            ForEach(AutoBeauty.looks) { l in Button(LocalizedStringKey(l.name)) { lookID = l.id; apply() }.buttonStyle(LumiButtonStyle()).lumiSelected(lookID == l.id) }
                            Button("Off") { model.edit { $0.face = FaceRetouch() } }.buttonStyle(LumiButtonStyle())
                        }
                        row("Strength", $strength, 0...1) { apply() }
                        Text("Makeup looks").font(.caption).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(MakeupLooks.all) { l in
                                    Button(LocalizedStringKey(l.name)) { applyMakeup(l) }.buttonStyle(LumiButtonStyle())
                                }
                            }.padding(.horizontal)
                        }
                        PhotosPicker("Recreate from photo", selection: $reference, matching: .images).padding(.top, 2)
                    case .ratio:
                        row("Move left/right", f(\.ratio.shiftX)); row("Move up/down", f(\.ratio.shiftY)); row("Rotate", f(\.ratio.rotate)); row("Symmetry", f(\.ratio.symmetry), 0...1)
                        row("Even out jaw", f(\.ratio.unevenFix), 0...1); row("3D shading", f(\.ratio.shade3D), 0...1)
                        Toggle("Protect eyes, nose and mouth", isOn: Binding(get: { model.draft.face.ratio.protectFeatures }, set: { v in model.edit { var fr = $0.face; fr.ratio.protectFeatures = v; $0.face = fr } })).padding(.horizontal)
                        Toggle("Lock glasses", isOn: Binding(get: { model.draft.face.ratio.glassesLock }, set: { v in model.edit { var fr = $0.face; fr.ratio.glassesLock = v; $0.face = fr } })).padding(.horizontal)
                    case .skin:
                        row("Smooth", f(\.skin.smooth), 0...1); row("Texture", f(\.skin.texture), 0...1); row("Whiten", f(\.skin.whiten), 0...1); row("Rosy", f(\.skin.rosy), 0...1); row("Tan", f(\.skin.tan), 0...1)
                    case .shape:
                        row("Jaw", f(\.reshape.jawSlim)); row("Face width", f(\.reshape.faceWidth)); row("Chin", f(\.reshape.chinLength)); row("Eyes", f(\.reshape.eyeSize)); row("Nose", f(\.reshape.noseSlim)); row("Mouth", f(\.reshape.mouthSize)); row("Cheek volume", f(\.reshape.cheekVolume)); row("Lift", f(\.reshape.lift))
                    case .makeup:
                        row("Lipstick", f(\.makeup.lipOpacity), 0...1); row("Blush", f(\.makeup.blushOpacity), 0...1); row("Lip shine", f(\.makeup.ombre), 0...1); row("Contour", f(\.makeup.contour), 0...1); row("Highlight", f(\.makeup.highlight), 0...1); row("Foundation", f(\.makeup.foundation), 0...1)
                    case .eyes:
                        row("Shadow", e(\.eyes.left.shadow, \.eyes.right.shadow), 0...1); row("Eyeliner", e(\.eyes.left.liner, \.eyes.right.liner), 0...1); row("Lashes", e(\.eyes.left.lashes, \.eyes.right.lashes), 0...1)
                        row("Brow color", f(\.eyes.browOpacity), 0...1); row("Brow height", f(\.eyes.browHeight))
                        Picker("Brow shape", selection: Binding(get: { model.draft.face.eyes.browShape }, set: { v in model.edit { var fr = $0.face; fr.eyes.browShape = v; $0.face = fr } })) {
                            ForEach(EyeMakeup.BrowShape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }.pickerStyle(.segmented).padding(.horizontal)
                    case .detail:
                        row("Flash", f(\.detail.flash), 0...1); row("Under-eye", f(\.detail.underEye), 0...1); row("Fine lines", f(\.detail.wrinkles), 0...1); row("Teeth", f(\.detail.teethWhiten), 0...1); row("Bright eyes", f(\.detail.eyeBright), 0...1)
                    }
                }
            }
        }
    }

    /// One slider that drives both eyes.
    private func e(_ l: WritableKeyPath<FaceRetouch, Double>, _ r: WritableKeyPath<FaceRetouch, Double>) -> Binding<Double> {
        Binding(get: { model.draft.face[keyPath: l] }, set: { model.draft.face[keyPath: l] = $0; model.draft.face[keyPath: r] = $0 })
    }

    private func applyMakeup(_ l: MakeupLook) {
        let s = MakeupLooks.scaled(l, strength: strength)
        model.edit { var f = $0.face; f.makeup = s.makeup; f.eyes = s.eyes; $0.face = f }
    }

    private func recreate(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let face = (try? VisionFaceLandmarker().faces(in: img))?.first else { referenceFailed = true; return }
        let look = RecreateLook.look(from: RecreateLook.sample(img, face: face))
        model.edit { var f = $0.face; f.makeup = look.makeup; f.eyes = look.eyes; $0.face = f }
    }

    private func apply() { if let l = AutoBeauty.looks.first(where: { $0.id == lookID }) { model.edit { $0.face = FaceRetouch.look(l, strength: strength) } } }

    private func f(_ path: WritableKeyPath<FaceRetouch, Double>) -> Binding<Double> {
        Binding(get: { model.draft.face[keyPath: path] }, set: { model.draft.face[keyPath: path] = $0 })
    }

    /// What each slider works on, so the preview can outline it.
    private static let marks: [String: FaceMark] = [
        "Jaw": .jaw, "Face width": .faceWidth, "Chin": .chin, "Eyes": .eyes, "Nose": .nose, "Mouth": .mouth, "Cheek volume": .cheeks, "Lift": .lift,
        "Move left/right": .face, "Move up/down": .face, "Rotate": .face, "Symmetry": .face, "Even out jaw": .jaw, "3D shading": .contour,
        "Smooth": .skin, "Texture": .skin, "Whiten": .skin, "Rosy": .skin, "Tan": .skin,
        "Lipstick": .lips, "Blush": .blush, "Lip shine": .lips, "Contour": .contour, "Highlight": .highlight, "Foundation": .skin,
        "Shadow": .eyes, "Eyeliner": .eyes, "Lashes": .eyes, "Brow color": .brows, "Brow height": .brows,
        "Flash": .skin, "Under-eye": .underEye, "Fine lines": .skin, "Teeth": .teeth, "Bright eyes": .eyes,
    ]

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double> = -1...1, onEnd: (() -> Void)? = nil) -> some View {
        let mark = Self.marks[title]
        return LumiSliderRow(title: LocalizedStringKey(title), value: value, range: range,
                             onEditing: { editing in if let mark { model.mark(mark, editing: editing) } },
                             onEnd: { if let onEnd { onEnd() } else { model.commit() } })
    }
}

struct LiquifyPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 8) {
            Picker("Brush", selection: Binding(get: { model.warpBrush.kind }, set: { model.warpBrush.kind = $0 })) {
                Text("Slim").tag(BrushStroke.Kind.push); Text("Zoom in").tag(BrushStroke.Kind.bloat); Text("Zoom out").tag(BrushStroke.Kind.pinch)
            }.pickerStyle(.segmented).padding(.horizontal)
            LumiSliderRow(title: "Size", value: Binding(get: { model.warpBrush.size }, set: { model.warpBrush.size = $0 }), range: 0.03...0.3, onEnd: { model.commit() })
            LumiSliderRow(title: "Strength", value: Binding(get: { model.warpBrush.strength }, set: { model.warpBrush.strength = $0 }), range: 0.1...1, onEnd: { model.commit() })
            Text("Drag on the photo. Undo steps back one drag.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LiquifyOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    @State private var path: [CGPoint] = []
    @State private var before: WarpEdit?
    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = map.toImageClamped(v.location)
                    if path.isEmpty { before = model.draft.warp }
                    path.append(CGPoint(x: p.x / imageSize.width, y: p.y / imageSize.height))
                    var w = before ?? WarpEdit()
                    model.warpBrush.strokes(for: path).forEach { w.add($0) }     // rebuilt from the whole drag, so the live preview matches the final result
                    model.draft.warp = w
                }
                .onEnded { _ in path = []; before = nil; model.commit() })
        }
    }
}

struct MarkPanel: View {
    @Bindable var model: EditorModel
    @State private var box = WatermarkBox()
    @State private var text = ""
    @State private var tiled = false
    @State private var opacity = 0.6
    @State private var size = 0.06

    private var current: Watermark { Watermark(name: text, kind: .text(text), opacity: opacity, size: size, isTiled: tiled) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                TextField("Your mark", text: $text).textFieldStyle(.roundedBorder)
                Button("Apply") { model.edit { $0.watermark = text.isEmpty ? nil : current } }.buttonStyle(LumiButtonStyle(prominent: true))
                Button("Save", systemImage: "star") { if !text.isEmpty { box.save(current) } }.labelStyle(.iconOnly).buttonStyle(LumiButtonStyle())
                Button("Off") { model.edit { $0.watermark = nil } }.buttonStyle(LumiButtonStyle())
            }.padding(.horizontal)
            HStack {
                ForEach(TimeStampStyle.allCases, id: \.self) { st in
                    Button(st.rawValue.capitalized) { text = WatermarkMath.timeStamp(.now, style: st) }.buttonStyle(LumiButtonStyle())
                }
                Toggle("Tiled", isOn: $tiled).fixedSize()
            }.padding(.horizontal)
            LumiSliderRow(title: "Opacity", value: $opacity, range: 0.1...1, onEnd: { model.commit() })
            LumiSliderRow(title: "Size", value: $size, range: 0.03...0.2, onEnd: { model.commit() })
            if !box.library.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(box.library.items) { w in
                            Button(w.name) { if case .text(let t) = w.kind { text = t }; tiled = w.isTiled; opacity = w.opacity; size = w.size; model.edit { $0.watermark = w } }
                                .buttonStyle(LumiButtonStyle()).contextMenu { Button("Delete", role: .destructive) { box.delete(w.id) } }
                        }
                    }.padding(.horizontal)
                }
            }
        }
    }
}

struct FilterEraserOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    @State private var remover: RemoverModel?

    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = map.toImageClamped(v.location)
                    if remover == nil { remover = RemoverModel(imageSize: imageSize); remover?.brushSize = 0.06; remover?.begin(at: p) } else { remover?.move(to: p) }
                    if let r = remover { model.draft.filterEraser = union(model.committedEraser, r.mask) }
                }
                .onEnded { _ in remover = nil; model.commit() })
        }
    }

    private func union(_ base: MaskCanvas?, _ add: MaskCanvas) -> MaskCanvas {
        guard var b = base, b.width == add.width, b.height == add.height else { return add }
        b.union(add); return b
    }
}

struct MosaicPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 8) {
            Picker("Style", selection: Binding(get: { model.draft.mosaic.style }, set: { v in model.edit { var m = $0.mosaic; m.style = v; $0.mosaic = m } })) {
                Text("Pixel").tag(MosaicOps.Style.pixel); Text("Blur").tag(MosaicOps.Style.blur)
            }.pickerStyle(.segmented).padding(.horizontal)
            LumiSliderRow(title: "Strength", value: Binding(get: { model.draft.mosaic.block }, set: { model.draft.mosaic.block = $0 }), range: 0.005...0.08, onEnd: { model.commit() })
            HStack {
                Toggle("Faces", isOn: Binding(get: { model.draft.mosaic.coverFaces }, set: { v in model.edit { var m = $0.mosaic; m.coverFaces = v; $0.mosaic = m } })).fixedSize()
                Toggle("Chat", isOn: Binding(get: { model.draft.mosaic.chatMode }, set: { v in model.edit { var m = $0.mosaic; m.chatMode = v; $0.mosaic = m } })).fixedSize()
                Button("Clear") { model.edit { $0.mosaic = MosaicConfig() } }.buttonStyle(LumiButtonStyle())
            }
            Text("Drag on the photo to cover an area by hand.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MosaicBrushOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    @State private var brush: RemoverModel?

    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = map.toImageClamped(v.location)
                    if brush == nil { brush = RemoverModel(imageSize: imageSize); brush?.brushSize = 0.05; brush?.begin(at: p) } else { brush?.move(to: p) }
                    if let b = brush { var m = model.draft.mosaic; m.masks = merged(model.stack0.mosaic.masks, b.mask); model.draft.mosaic = m }
                }
                .onEnded { _ in brush = nil; model.commit() })
        }
    }

    /// One accumulated mask: earlier strokes plus the current drag.
    private func merged(_ earlier: [MaskCanvas], _ current: MaskCanvas) -> [MaskCanvas] {
        guard var base = earlier.first, base.width == current.width, base.height == current.height else { return earlier + [current] }
        base.union(current); return [base]
    }
}

struct LayerGestureOverlay: View {
    @Bindable var model: EditorModel
    @State private var baseScale = 1.0
    @State private var baseRotation = 0.0

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        guard let o = model.original else { return }
                        let map = FitMapping(view: box, image: o.extent.size), d = map.displayed
                        model.moveSelected(to: CGPoint(x: (v.location.x - d.minX) / max(d.width, 1), y: (v.location.y - d.minY) / max(d.height, 1)))
                    }.onEnded { _ in model.commit() })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { v in if baseScale == 1 { baseScale = model.selectedLayerValue?.transform.scale ?? 1 }; model.scaleSelected(base: baseScale, by: v.magnification) }
                    .onEnded { _ in baseScale = 1; model.commit() })
                .simultaneousGesture(RotateGesture()
                    .onChanged { v in if baseRotation == 0 { baseRotation = model.selectedLayerValue?.transform.rotation ?? 0 }; model.rotateSelected(base: baseRotation, by: v.rotation.radians) }
                    .onEnded { _ in baseRotation = 0; model.commit() })
        }
        .allowsHitTesting(model.selectedLayer != nil)
    }
}

struct HairPanel: View {
    @Bindable var model: EditorModel
    @State private var category = "Natural"
    private var categories: [String] { var s = Set<String>(); return HairRetouch.swatches.map(\.category).filter { s.insert($0).inserted } }

    var body: some View {
        VStack(spacing: 4) {
            Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Text(LocalizedStringKey($0)).tag($0) } }.pickerStyle(.segmented).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Off") { model.edit { $0.hair = HairRetouch() } }.buttonStyle(LumiButtonStyle())
                    ForEach(HairRetouch.swatches.filter { $0.category == category }, id: \.name) { s in
                        Button { model.edit { var h = $0.hair; h.dye.color = s.color; h.dye.strength = max(h.dye.strength, 0.8); $0.hair = h } } label: {
                            Circle().fill(Color(red: s.color.r, green: s.color.g, blue: s.color.b)).frame(width: 34, height: 34).overlay(Circle().stroke(.secondary, lineWidth: 1))
                        }.accessibilityLabel(Text(LocalizedStringKey(s.name)))
                    }
                }.padding(.horizontal)
            }
            row("Dye", \.hair.dye.strength); row("Keep shine", \.hair.dye.keepShine); row("De-oil", \.hair.deOil); row("Smooth", \.hair.smooth); row("Roots", \.hair.rootRetouch)
            row("Volume", \.hair.volume, -1...1); row("Hairline", \.hair.hairline, -1...1); row("Glow", \.hair.glow); row("Flyaways", \.hair.flyaway)
            HStack {
                Toggle("Brush", isOn: $model.hairBrushActive).fixedSize()
                Picker("Mode", selection: $model.hairBrushMode) { Text("Add").tag(HairBrushMode.add); Text("Erase").tag(HairBrushMode.erase); Text("Fill").tag(HairBrushMode.fill) }.pickerStyle(.segmented)
            }.padding(.horizontal)
        }
    }

    private func row(_ title: String, _ path: WritableKeyPath<EditDocument, Double>, _ range: ClosedRange<Double> = 0...1) -> some View {
        LumiSliderRow(title: LocalizedStringKey(title), value: Binding(get: { model.draft[keyPath: path] }, set: { model.draft[keyPath: path] = $0 }), range: range, onEnd: { model.commit() })
    }
}

struct HairBrushOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    @State private var brush: RemoverModel?

    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = map.toImageClamped(v.location)
                    if brush == nil { brush = RemoverModel(imageSize: imageSize); brush?.brushSize = 0.04; brush?.begin(at: p) } else { brush?.move(to: p) }
                    if let b = brush { apply(b.mask) }
                }
                .onEnded { _ in brush = nil; model.commit() })
        }
    }

    private func apply(_ stroke: MaskCanvas) {
        var h = model.draft.hair
        let committed = model.stack0.hair
        func merged(_ base: MaskCanvas?) -> MaskCanvas { guard var b = base, b.width == stroke.width, b.height == stroke.height else { return stroke }; b.union(stroke); return b }
        switch model.hairBrushMode {
        case .add: h.add = merged(committed.add)
        case .erase: h.remove = merged(committed.remove)
        case .fill: h.fill = merged(committed.fill)
        }
        model.draft.hair = h
    }
}


/// Clone stamp: paint where the copy should land; the source is the same spot moved by the offset sliders.
struct CleanPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 4) {
            Text("Paint over what to hide. It is covered with the area at the offset.").font(.caption).foregroundStyle(.secondary)
            slider("Source ←→", \.offsetX, -0.5...0.5)
            slider("Source ↑↓", \.offsetY, -0.5...0.5)
            slider("Noise reduction", \.denoise, 0...1)
            Button("Clear clone") { model.edit { var c = $0.clean; c.cloneMask = nil; $0.clean = c } }.buttonStyle(LumiButtonStyle())
        }
    }
    private func slider(_ title: String, _ path: WritableKeyPath<CleanConfig, Double>, _ range: ClosedRange<Double>) -> some View {
        LumiSliderRow(title: LocalizedStringKey(title), value: Binding(get: { model.draft.clean[keyPath: path] }, set: { model.draft.clean[keyPath: path] = $0 }), range: range, onEnd: { model.commit() })
    }
}

struct CleanBrushOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    @State private var remover: RemoverModel?

    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = map.toImageClamped(v.location)
                    if remover == nil { remover = RemoverModel(imageSize: imageSize); remover?.brushSize = 0.05; remover?.begin(at: p) } else { remover?.move(to: p) }
                    if let r = remover {
                        var c = model.draft.clean
                        if var base = model.stack0.clean.cloneMask, base.width == r.mask.width, base.height == r.mask.height { base.union(r.mask); c.cloneMask = base } else { c.cloneMask = r.mask }
                        model.draft.clean = c
                    }
                }
                .onEnded { _ in remover = nil; model.commit() })
        }
    }
}
