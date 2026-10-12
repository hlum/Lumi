import PhotosUI
import SwiftData
import SwiftUI

enum EditorCategory: String, CaseIterable, Identifiable {
    case edit = "Edit", retouch = "Retouch", body = "Body", hair = "Hair", makeup = "Makeup"
    var id: String { rawValue }
}

enum EditorTool: String, CaseIterable, Identifiable {
    case adjust = "Adjust", crop = "Crop", text = "Text", remove = "Remove", cutout = "Cutout", filter = "Filters", sticker = "Stickers", frame = "Frame", doodle = "Doodle", hair = "Hair", mosaic = "Mosaic", mark = "Mark", liquify = "Manual slim", clean = "Clean", face = "Face", makeup = "Makeup", color = "Color", enhance = "Enhance", export = "Export"
    case relight = "AI Flash", effects = "Effects", expand = "Expand"
    case autoBeauty = "Auto beauty", skin = "Skin", reshape = "Reshape", blemish = "Blemishes", eyesTeeth = "Eyes and teeth", underEye = "Under-eye", body = "Body"
    case looks = "Looks", lips = "Lips", eyeMakeup = "Eyes", nails = "Nails"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .adjust: "slider.horizontal.3"; case .crop: "crop.rotate"; case .text: "textformat"; case .remove: "eraser"; case .cutout: "person.crop.rectangle"; case .filter: "camera.filters"
        case .sticker: "face.smiling"; case .frame: "photo.artframe"; case .doodle: "scribble"; case .color: "paintpalette"; case .face: "face.smiling.inverse"; case .makeup: "wand.and.stars"
        case .liquify: "hand.draw"; case .clean: "bandage"; case .mark: "checkmark.seal"; case .mosaic: "square.grid.3x3.fill"; case .hair: "comb"; case .enhance: "sparkles"; case .export: "square.and.arrow.up.on.square"
        case .autoBeauty: "sparkle.magnifyingglass"; case .skin: "face.dashed"; case .reshape: "person.crop.circle.badge.questionmark"; case .blemish: "circle.dotted"; case .eyesTeeth: "eye"; case .underEye: "moon.zzz"
        case .relight: "bolt.fill"; case .effects: "sparkle"; case .expand: "arrow.up.left.and.arrow.down.right.circle"
        case .body: "figure.stand"; case .looks: "sparkles.rectangle.stack"; case .lips: "mouth"; case .eyeMakeup: "eyebrow"; case .nails: "hand.raised.fingers.spread"
        }
    }
    var category: EditorCategory {
        switch self {
        case .face, .autoBeauty, .skin, .reshape, .blemish, .eyesTeeth, .underEye: .retouch
        case .liquify, .body: .body
        case .hair: .hair
        case .makeup, .looks, .lips, .eyeMakeup, .nails: .makeup
        default: .edit
        }
    }
    /// Tools that work on faces: they need the detected faces for the outlines.
    var usesFaces: Bool { [.face, .makeup, .autoBeauty, .skin, .reshape, .blemish, .eyesTeeth, .underEye, .looks, .lips, .eyeMakeup].contains(self) }
    /// Tools shown in a category's grid, in order. Export is reached from Save.
    static func tools(in c: EditorCategory) -> [EditorTool] {
        switch c {
        case .edit: [.crop, .adjust, .filter, .color, .relight, .text, .sticker, .remove, .cutout, .expand, .effects, .enhance, .frame, .doodle, .mosaic, .mark]
        case .retouch: [.autoBeauty, .skin, .reshape, .blemish, .eyesTeeth, .underEye]
        case .body: [.body, .liquify]
        case .hair: [.hair]
        case .makeup: [.looks, .lips, .eyeMakeup, .nails]
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
            .overlay { toolOverlay(previewSize: size) }
            .overlay(alignment: .bottomTrailing) {
                Label("Compare", systemImage: "eye").font(.system(size: 14, weight: .bold, design: .rounded))
                    .padding(.horizontal, 14).frame(height: 36).background(Capsule().fill(.white.opacity(0.9))).foregroundStyle(.black).padding(12)
                    .onLongPressGesture(minimumDuration: 0.1, pressing: { model.showOriginal = $0 }, perform: {})
                    .accessibilityLabel("Hold to compare with original")
            }
            .clipShape(RoundedRectangle(cornerRadius: LumiShape.photo, style: .continuous))
            .padding(.horizontal, LumiShape.margin)
    }

    /// What is drawn or caught on top of the photo while a tool is open: brushes, outlines, the crop frame.
    @ViewBuilder private func toolOverlay(previewSize size: CGSize) -> some View {
        let original = model.original?.extent.size
        ZStack {
            if let t = tool {
                if t.usesFaces { FaceMarksOverlay(mark: model.activeMark, faces: model.overlayFaces, imageSize: size) }
                switch t {
                case .text, .sticker: LayerGestureOverlay(model: model)
                case .hair:
                    HairMaskOverlay(image: model.hairOverlay, visible: model.hairBrushActive, imageSize: size)
                    if model.hairBrushActive, let o = original { HairBrushOverlay(model: model, imageSize: o) }
                case .mosaic: if let o = original { MosaicBrushOverlay(model: model, imageSize: o) }
                case .filter: if model.filterEraserActive, let o = original { FilterEraserOverlay(model: model, imageSize: o) }
                case .relight, .effects:
                    if model.lightEraserActive { MaskPaintOverlay(model: model, imageSize: size, committed: { model.stack0.relight.erase }, write: { m in var r = model.draft.relight; r.erase = m; model.draft.relight = r }) }
                case .blemish: BlemishTapOverlay(model: model, imageSize: size)
                case .crop: CropOverlay(model: model, imageSize: size)
                case .clean: if let o = original { CleanBrushOverlay(model: model, imageSize: o) }
                case .liquify: if let o = original { LiquifyOverlay(model: model, imageSize: o) }
                case .doodle: if let o = original { DoodleOverlay(model: model, imageSize: o) }
                case .remove:
                    if model.cloneActive, let o = original { CleanBrushOverlay(model: model, imageSize: o) }
                    else if let r = model.remover, let o = original { RemoverOverlay(remover: r, imageSize: o) }
                default: EmptyView()
                }
            }
        }
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
        case .relight: RelightPanel(model: model)
        case .expand: ExpandPanel(model: model)
        case .effects: EffectsPanel(model: model)
        case .autoBeauty: AutoBeautyPanel(model: model)
        case .skin: SkinPanel(model: model)
        case .reshape: ReshapePanel(model: model)
        case .blemish: BlemishPanel(model: model)
        case .eyesTeeth: EyesTeethPanel(model: model)
        case .underEye: UnderEyePanel(model: model)
        case .body: BodyPanel(model: model)
        case .looks: LooksPanel(model: model)
        case .lips: LipsPanel(model: model)
        case .eyeMakeup: EyeMakeupPanel(model: model)
        case .nails: NailsPanel(model: model)
        case .color: ColorPanel(model: model)
        case .enhance: EnhancePanel(model: model)
        case .export: ExportPanel(model: model)
        }
    }

    private func open(_ t: EditorTool) { snapshot = model.stack0; tool = t; model.cropEditing = (t == .crop); model.cropAspect = nil; if t.usesFaces { model.refreshOverlayFaces() } }
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
    @State private var mode = Mode.add
    @State private var lines: [TextLine] = []
    @State private var picked: TextLine?
    @State private var replacement = ""
    @State private var searching = false
    @State private var searched = false
    @State private var ideas: [String] = []
    enum Mode: String, CaseIterable { case add = "Add text", change = "Change text in photo" }

    var body: some View {
        VStack(spacing: 12) {
            LumiSegmented(items: Mode.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $mode, height: 40)
            if mode == .add { addBody } else { changeBody }
        }
        .task { if ideas.isEmpty, let o = model.original { ideas = await SceneCaptionSuggester().suggestions(for: Renderer.proxy(o, maxDimension: 512)) } }
    }

    private var changeBody: some View {
        VStack(spacing: 10) {
            if !searched {
                Text("Finds the text in the photo so you can change it. The old words are erased and the new ones match the colour and size.").font(.footnote).foregroundStyle(LumiColor.textSecondary)
                LumiPrimaryButton(title: searching ? "Looking…" : "Find text", symbol: "text.viewfinder", disabled: searching) { find() }
            } else if lines.isEmpty {
                Text("No text found in this photo.").font(LumiFont.body())
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(lines) { l in LumiChip(title: LocalizedStringKey(l.text), selected: picked == l) { picked = l; replacement = l.text } } }
                }
                if picked != nil {
                    TextField("New text", text: $replacement).lumiField()
                    LumiPrimaryButton(title: "Replace", symbol: "arrow.triangle.2.circlepath", disabled: replacement.trimmingCharacters(in: .whitespaces).isEmpty) { replace() }
                }
            }
        }
    }

    private func find() {
        guard let o = model.original else { return }
        searching = true
        Task {
            let proxy = Renderer.proxy(o, maxDimension: 1600)
            let found = await Task.detached { (try? VisionTextReader().lines(in: proxy)) ?? [] }.value
            lines = found; searched = true; searching = false
        }
    }

    private func replace() {
        guard let o = model.original, let line = picked, let plan = ReplaceText.plan(line: line, newText: replacement, in: Renderer.proxy(o, maxDimension: 1600), fontName: font) else { return }
        model.edit { d in
            d.removals = d.removals + [plan.mask]
            var s = d.layers; try? s.add(plan.layer); d.layers = s
        }
        model.selectedLayer = plan.layer.id
        picked = nil; searched = false; lines = []
    }

    private var addBody: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Add text", text: $text).lumiField()
                LumiIconButton(symbol: "plus", label: "Add text", dark: true, disabled: text.trimmingCharacters(in: .whitespaces).isEmpty) {
                    var style = preset?.style ?? TextStyle(); style.fontName = font
                    var layer = Layer(content: .text(text, style)); layer.behindSubject = behind
                    model.edit { d in var s = d.layers; try? s.add(layer); d.layers = s }; model.selectedLayer = layer.id   // the stack rejects empty text
                    text = ""
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(FontLibrary.all) { f in LumiChip(title: LocalizedStringKey(f.name), selected: font == f.postScript) { font = f.postScript } } }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(TextStylePresets.all) { p in LumiChip(title: LocalizedStringKey(p.name), selected: preset == p) { font = p.style.fontName; preset = p } } }
            }
            if !ideas.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(ideas, id: \.self) { i in LumiChip(title: LocalizedStringKey(i), symbol: "lightbulb") { text = i } } } } }
            LumiToggleRow(title: "Behind subject", subtitle: "Text slips behind the person", isOn: $behind)
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
    @State private var thumbs: [String: UIImage] = [:]
    private let library = FilterLibrary.shared
    private let favorites = "★"

    private var shown: [FilterEntry] {
        if category == favorites { return prefs.prefs.favorites.compactMap { library.entry($0) } }
        if category == "Recent" { return prefs.prefs.recents.compactMap { library.entry($0) } }
        return library.entries(in: category).filter { !prefs.prefs.hidden.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 12) {
            LumiCategoryTabs(items: [(favorites, LocalizedStringKey("★ Favorites")), ("Recent", "Recent")] + library.categories.map { ($0, LocalizedStringKey($0.capitalized)) }, selection: $category)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    tile(id: nil, title: "None", on: model.draft.filter == nil) { model.edit { $0.filter = nil; $0.filterEraser = nil } }
                    ForEach(shown) { e in
                        tile(id: e.id, title: e.name, on: model.draft.filter?.id == e.id) { prefs.used(e.id); let keep = model.draft.filter?.intensity ?? 0.8; model.edit { $0.filter = (e.id, keep) } }
                    }
                }
            }
            LumiSliderRow(title: "Strength", value: Binding(get: { model.draft.filter?.intensity ?? 1 }, set: { v in if let f = model.draft.filter { model.draft.filter = (f.id, v) } }), range: 0...1, defaultValue: 0.8, onEnd: { model.commit() })
                .disabled(model.draft.filter == nil).opacity(model.draft.filter == nil ? 0.5 : 1)
            HStack(spacing: 8) {
                LumiChip(title: "Auto colour fix", symbol: "wand.and.stars") { model.autoFix() }
                if let id = model.draft.filter?.id {
                    LumiChip(title: prefs.isFavorite(id) ? "Unfavourite" : "Favourite", symbol: prefs.isFavorite(id) ? "star.fill" : "star") { prefs.toggleFavorite(id) }
                    LumiChip(title: "Eraser", selected: erasing, symbol: "eraser") { erasing.toggle() }
                    if erasing, model.draft.filterEraser != nil { LumiChip(title: "Clear") { model.edit { $0.filterEraser = nil } } }
                }
            }
            if erasing { Text("Paint where the filter should go away").font(.footnote).foregroundStyle(LumiColor.textSecondary) }
        }
        .task(id: category) { await loadThumbs() }
        .onChange(of: erasing) { _, on in model.filterEraserActive = on }
        .onDisappear { model.filterEraserActive = false }
    }

    private func tile(id: String?, title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let id, let img = thumbs[id] { Image(uiImage: img).resizable().scaledToFill() }
                    else { LumiColor.well.overlay(Image(systemName: id == nil ? "nosign" : "photo").foregroundStyle(LumiColor.textSecondary)) }
                }
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? LumiColor.accent : .clear, lineWidth: 3))
                Text(LocalizedStringKey(title)).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(LumiColor.text).lineLimit(1).frame(width: 68)
            }
        }
        .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Each filter applied to a small copy of the photo, one at a time off the main thread.
    private func loadThumbs() async {
        guard let source = model.thumbnailSource() else { return }
        let entries = shown.filter { thumbs[$0.id] == nil }
        for e in entries {
            if Task.isCancelled { return }
            let id = e.id
            let img: UIImage? = await Task.detached(priority: .utility) {
                guard let lut = FilterLibrary.shared.lut(id) else { return nil }
                let out = lut.apply(to: source, intensity: 1)
                guard let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
                return UIImage(cgImage: cg)
            }.value
            if let img { thumbs[id] = img }
        }
    }
}

struct StickerPanel: View {
    @Bindable var model: EditorModel
    @State private var query = ""
    @State private var outline = 0.0
    @State private var noSubject = false

    var body: some View {
        VStack {
            TextField("Search stickers", text: $query).lumiField()
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
            LumiSegmented(items: FrameConfig.Style.allCases.map { ($0, LocalizedStringKey($0.rawValue.capitalized)) }, selection: Binding(get: { model.draft.frame.style }, set: { v in model.edit { var f = $0.frame; f.style = v; if f.padding == 0 { f.padding = 0.04 }; $0.frame = f } }), height: 40)
            LumiSliderRow(title: "Padding", value: Binding(get: { model.draft.frame.padding }, set: { model.draft.frame.padding = $0 }), range: 0...0.25, onEnd: { model.commit() })
            LumiSwatchRow(colors: [("White", RGBA.white), ("Black", RGBA.black), ("Cream", RGBA(r: 1, g: 0.95, b: 0.8, a: 1)), ("Blush", RGBA(r: 0.98, g: 0.82, b: 0.85, a: 1)), ("Sky", RGBA(r: 0.7, g: 0.85, b: 0.98, a: 1))], selected: model.draft.frame.color) { c in model.edit { var f = $0.frame; f.color = c; $0.frame = f } }
        }
    }
}

struct DoodlePanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(DoodleStroke.Brush.allCases, id: \.self) { b in LumiChip(title: LocalizedStringKey(b.rawValue.capitalized), selected: model.doodleBrush == b) { model.doodleBrush = b } } }
            }
            LumiSwatchRow(colors: [("Red", RGBA(r: 1, g: 0.3, b: 0.35, a: 1)), ("Yellow", RGBA(r: 1, g: 0.85, b: 0.2, a: 1)), ("Blue", RGBA(r: 0.3, g: 0.6, b: 1, a: 1)), ("Green", RGBA(r: 0.3, g: 0.8, b: 0.5, a: 1)), ("White", RGBA.white), ("Black", RGBA.black)], selected: model.doodleColor) { model.doodleColor = $0 }
            HStack { LumiChip(title: "Undo stroke", symbol: "arrow.uturn.backward") { model.edit { $0.doodle = Array($0.doodle.dropLast()) } }.disabled(model.draft.doodle.isEmpty); Spacer() }
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
                Text("Sharper, bigger photo. Applied when you save.").font(.footnote).foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    LumiChip(title: "Off", selected: model.draft.upscale == nil) { model.edit { $0.upscale = nil } }
                    LumiChip(title: "HD  2×", selected: model.draft.upscale == 2) { model.edit { $0.upscale = 2 } }
                    LumiChip(title: "Ultra HD  4×", selected: model.draft.upscale == 4) { model.edit { $0.upscale = 4 } }
                }
            } else {
                Text("Enhance works on photos up to 2048 px on the long side, with the model installed.").font(.footnote).foregroundStyle(LumiColor.textSecondary).padding()
            }
            if SiggraphColorizer.isModelAvailable, let o = model.original, max(o.extent.width, o.extent.height) <= CGFloat(SiggraphColorizer.maxInputSide) {
                HStack(spacing: 8) {
                    Text("Add colour").font(LumiFont.caption())
                    LumiChip(title: "Off", selected: model.draft.colorize == nil) { model.edit { $0.colorize = nil } }
                    LumiChip(title: "50%", selected: model.draft.colorize == 0.5) { model.edit { $0.colorize = 0.5 } }
                    LumiChip(title: "100%", selected: model.draft.colorize == 1) { model.edit { $0.colorize = 1 } }
                }
            }
            if let o = model.original {
                Button {
                    let plan = OldPhotoRestore.plan(for: o, canUpscale: model.canUpscale, canColorize: SiggraphColorizer.isModelAvailable)
                    model.edit { $0 = OldPhotoRestore.apply(plan, to: $0) }
                } label: {
                    Label("Restore old photo", systemImage: "wand.and.stars").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(LumiColor.onSelectedPill).background(Capsule().fill(LumiColor.selectedPill))
                }.buttonStyle(.plain)
            }
        }
    }
}

struct ExportPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 10) {
            LumiSegmented(items: ImageFormat.allCases.map { ($0, LocalizedStringKey($0.rawValue.uppercased())) }, selection: $model.exportSettings.format, height: 40)
            if model.exportSettings.format != .png {
                LumiSliderRow(title: "Quality", value: $model.exportSettings.quality, range: 0.3...1, onEnd: { model.commit() })
            }
            LumiSegmented(items: [(0, LocalizedStringKey("Original")), (4096, LocalizedStringKey("4096")), (2048, LocalizedStringKey("2048")), (1080, LocalizedStringKey("1080"))], selection: Binding(get: { model.exportSettings.maxLongSide ?? 0 }, set: { model.exportSettings.maxLongSide = $0 == 0 ? nil : $0 }), height: 40)
            HStack(spacing: 8) {
                Text("Print").font(LumiFont.caption())
                LumiChip(title: "10×15 cm") { model.applyPrintSize(width: 10, height: 15, unit: .cm, dpi: 300) }
                LumiChip(title: "A4") { model.applyPrintSize(width: 210, height: 297, unit: .mm, dpi: 300) }
                LumiChip(title: "Off") { model.clearPrintSize() }
            }
            if let s = model.exportPixelSize, let b = model.estimatedBytes {
                Text("\(s.w) × \(s.h) px · about \(ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file))").font(.footnote).foregroundStyle(LumiColor.textSecondary)
            }
        }
    }
}

struct ColorPanel: View {
    enum Section: String, CaseIterable { case curves = "Curves", hsl = "HSL", split = "Split", match = "Match" }
    enum Channel: String, CaseIterable { case rgb = "RGB", red = "R", green = "G", blue = "B" }
    @Bindable var model: EditorModel
    @State private var section = Section.curves
    @State private var band = 0
    @State private var channel = Channel.rgb
    @State private var reference: PhotosPickerItem?
    @State private var failed = false

    private var curveBinding: Binding<ToneCurve> {
        Binding(get: {
            switch channel { case .rgb: model.draft.grade.rgbCurve; case .red: model.draft.grade.redCurve; case .green: model.draft.grade.greenCurve; case .blue: model.draft.grade.blueCurve }
        }, set: { v in
            switch channel { case .rgb: model.draft.grade.rgbCurve = v; case .red: model.draft.grade.redCurve = v; case .green: model.draft.grade.greenCurve = v; case .blue: model.draft.grade.blueCurve = v }
        })
    }

    var body: some View {
        VStack(spacing: 12) {
            LumiSegmented(items: Section.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $section, height: 40)
            switch section {
            case .curves:
                HStack(alignment: .top, spacing: 12) {
                    CurveGraph(curve: curveBinding, tint: channel == .red ? .red : channel == .green ? .green : channel == .blue ? .blue : LumiColor.text, onEnd: { model.commit() }).frame(height: 170)
                    VStack(spacing: 6) {
                        ForEach(Channel.allCases, id: \.self) { c in
                            Button { channel = c } label: {
                                Text(c.rawValue).font(.system(size: 13, weight: .heavy, design: .rounded)).frame(width: 40, height: 40)
                                    .foregroundStyle(channel == c ? LumiColor.onSelectedPill : (c == .red ? .red : c == .green ? .green : c == .blue ? .blue : LumiColor.text))
                                    .background(Circle().fill(channel == c ? LumiColor.selectedPill : LumiColor.well))
                            }.buttonStyle(.plain).accessibilityLabel(c == .rgb ? "All channels" : c == .red ? "Red channel" : c == .green ? "Green channel" : "Blue channel")
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ColorGrade.curvePresets.keys.sorted(), id: \.self) { name in
                            LumiChip(title: LocalizedStringKey(name.capitalized)) { let c = ColorGrade.curvePresets[name]!; model.edit { $0.grade.rgbCurve = c.rgb; $0.grade.redCurve = c.r; $0.grade.greenCurve = c.g; $0.grade.blueCurve = c.b } }
                        }
                        LumiChip(title: "Reset", symbol: "arrow.counterclockwise") { model.edit { $0.grade.rgbCurve = ToneCurve(); $0.grade.redCurve = ToneCurve(); $0.grade.greenCurve = ToneCurve(); $0.grade.blueCurve = ToneCurve() } }
                    }
                }
            case .hsl:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<8, id: \.self) { i in
                            let c = ColorGrade.rgb(ColorGrade.bandCenters[i], 0.85, 0.5)
                            Button { band = i } label: {
                                Circle().fill(Color(red: c.0, green: c.1, blue: c.2)).frame(width: 34, height: 34)
                                    .padding(4).overlay(Circle().strokeBorder(band == i ? LumiColor.selectedPill : .clear, lineWidth: 2)).frame(minWidth: 44, minHeight: 44)
                            }.buttonStyle(.plain).accessibilityLabel(Text(ColorGrade.bandNames[i]))
                        }
                    }
                }
                slider("Hue", Binding(get: { model.draft.grade.bands[band].hue }, set: { model.draft.grade.bands[band].hue = $0 }))
                slider("Saturation", Binding(get: { model.draft.grade.bands[band].sat }, set: { model.draft.grade.bands[band].sat = $0 }))
                slider("Luminance", Binding(get: { model.draft.grade.bands[band].lum }, set: { model.draft.grade.bands[band].lum = $0 }))
            case .split:
                slider("Shadow tint", Binding(get: { model.draft.grade.shadows.sat }, set: { model.draft.grade.shadows.sat = $0 }), range: 0...1)
                slider("Shadow hue", Binding(get: { model.draft.grade.shadows.hue / 360 }, set: { model.draft.grade.shadows.hue = $0 * 360 }), range: 0...1)
                slider("Highlight tint", Binding(get: { model.draft.grade.highlights.sat }, set: { model.draft.grade.highlights.sat = $0 }), range: 0...1)
                slider("Highlight hue", Binding(get: { model.draft.grade.highlights.hue / 360 }, set: { model.draft.grade.highlights.hue = $0 * 360 }), range: 0...1)
                slider("Balance", Binding(get: { model.draft.grade.balance }, set: { model.draft.grade.balance = $0 }))
                Stepper("Posterize: \(model.draft.grade.posterize == 0 ? "off" : "\(model.draft.grade.posterize)")", value: Binding(get: { model.draft.grade.posterize }, set: { v in model.edit { $0.grade.posterize = v == 1 ? 2 : v } }), in: 0...16)
                    .font(LumiFont.chip())
            case .match:
                let subtitle = model.draft.colorMatch.isIdentity ? "Choose a reference" : (model.draft.colorMatch.name.isEmpty ? "Reference chosen" : model.draft.colorMatch.name)
                PhotosPicker(selection: $reference, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle").foregroundStyle(LumiColor.accentText)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Copy colours from a photo").font(LumiFont.chip())
                            Text(subtitle).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(LumiColor.textSecondary)
                        }
                        Spacer()
                        Text("Change").font(LumiFont.chip())
                    }
                    .foregroundStyle(LumiColor.text).padding(.horizontal, 14).frame(minHeight: 60).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LumiColor.well))
                }
                slider("Strength", Binding(get: { model.draft.colorMatch.strength }, set: { model.draft.colorMatch.strength = $0 }), range: 0...1)
                    .disabled(model.draft.colorMatch.mean.isEmpty).opacity(model.draft.colorMatch.mean.isEmpty ? 0.5 : 1)
                if !model.draft.colorMatch.mean.isEmpty { LumiChip(title: "Remove match", symbol: "xmark") { model.edit { $0.colorMatch = ColorMatch() } } }
                if let o = model.original {
                    Text("Colours in this photo").font(LumiFont.caption()).foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                    LumiSwatchRow(colors: ColorSampler.palette(Renderer.proxy(o, maxDimension: 256), count: 8).enumerated().map { ("c\($0.offset)", RGBA(r: $0.element.r, g: $0.element.g, b: $0.element.b, a: 1)) }, selected: nil) { _ in }
                }
            }
        }
        .onChange(of: reference) { _, new in Task { await load(new) } }
        .alert("Couldn't read that photo", isPresented: $failed) {}
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = CIImage(data: data, options: [.applyOrientationProperty: true]),
              var m = ColorMatch.from(reference: img, name: "From photo") else { failed = true; return }
        m.strength = max(model.draft.colorMatch.strength, 0.7)
        model.edit { $0.colorMatch = m }
    }

    private func slider(_ title: String, _ value: Binding<Double>, range: ClosedRange<Double> = -1...1) -> some View {
        LumiSliderRow(title: LocalizedStringKey(title), value: value, range: range, onEnd: { model.commit() })
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
        "Move left/right": .face, "Move up/down": .face, "Rotate": .face, "Symmetry": .face, "Even out jaw": .jaw, "Brow height": .brows,
    ]   // shape sliders only: colour, skin and makeup sliders show no outline, so nothing hides what they change

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
            LumiSegmented(items: [(BrushStroke.Kind.push, LocalizedStringKey("Push")), (BrushStroke.Kind.pinch, LocalizedStringKey("Slim")), (BrushStroke.Kind.bloat, LocalizedStringKey("Fuller"))], selection: Binding(get: { model.warpBrush.kind }, set: { model.warpBrush.kind = $0 }), height: 44)
            LumiSliderRow(title: "Size", value: Binding(get: { model.warpBrush.size }, set: { model.warpBrush.size = $0 }), range: 0.03...0.3, onEnd: { model.commit() })
            LumiSliderRow(title: "Strength", value: Binding(get: { model.warpBrush.strength }, set: { model.warpBrush.strength = $0 }), range: 0.1...1, onEnd: { model.commit() })
            Text("Drag on the photo. Undo steps back one drag.").font(.footnote).foregroundStyle(LumiColor.textSecondary)
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
            HStack(spacing: 8) {
                TextField("Your mark", text: $text).lumiField()
                LumiIconButton(symbol: "checkmark", label: "Apply mark", dark: true) { model.edit { $0.watermark = text.isEmpty ? nil : current } }
                LumiIconButton(symbol: "star", label: "Save mark") { if !text.isEmpty { box.save(current) } }
                LumiIconButton(symbol: "xmark", label: "Remove mark") { model.edit { $0.watermark = nil } }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TimeStampStyle.allCases, id: \.self) { st in LumiChip(title: LocalizedStringKey(st.rawValue.capitalized), symbol: "calendar") { text = WatermarkMath.timeStamp(.now, style: st) } }
                    LumiChip(title: "Tiled", selected: tiled) { tiled.toggle() }
                }
            }
            LumiSliderRow(title: "Opacity", value: $opacity, range: 0.1...1, onEnd: { model.commit() })
            LumiSliderRow(title: "Size", value: $size, range: 0.03...0.2, onEnd: { model.commit() })
            if !box.library.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(box.library.items) { w in
                            LumiChip(title: LocalizedStringKey(w.name)) { if case .text(let t) = w.kind { text = t }; tiled = w.isTiled; opacity = w.opacity; size = w.size; model.edit { $0.watermark = w } }
                                .contextMenu { Button("Delete", role: .destructive) { box.delete(w.id) } }
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
            LumiSegmented(items: [(MosaicOps.Style.pixel, LocalizedStringKey("Pixel")), (MosaicOps.Style.blur, LocalizedStringKey("Blur"))], selection: Binding(get: { model.draft.mosaic.style }, set: { v in model.edit { var m = $0.mosaic; m.style = v; $0.mosaic = m } }), height: 40)
            LumiSliderRow(title: "Strength", value: Binding(get: { model.draft.mosaic.block }, set: { model.draft.mosaic.block = $0 }), range: 0.005...0.08, onEnd: { model.commit() })
            LumiToggleRow(title: "Cover faces", subtitle: nil, isOn: Binding(get: { model.draft.mosaic.coverFaces }, set: { v in model.edit { var m = $0.mosaic; m.coverFaces = v; $0.mosaic = m } }))
            LumiToggleRow(title: "Chat screenshot", subtitle: "Covers names and message text", isOn: Binding(get: { model.draft.mosaic.chatMode }, set: { v in model.edit { var m = $0.mosaic; m.chatMode = v; $0.mosaic = m } }))
            HStack { Text("Drag on the photo to cover an area by hand.").font(.footnote).foregroundStyle(LumiColor.textSecondary); Spacer(); LumiChip(title: "Clear") { model.edit { $0.mosaic = MosaicConfig() } } }
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
    enum Tab: String, CaseIterable { case colour = "Colour", shape = "Shape", brush = "Brush" }
    @Bindable var model: EditorModel
    @State private var tab = Tab.colour
    @State private var category = "Natural"
    private var categories: [String] { var s = Set<String>(); return HairRetouch.swatches.map(\.category).filter { s.insert($0).inserted } }

    var body: some View {
        VStack(spacing: 12) {
            LumiSegmented(items: Tab.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $tab, height: 40)
            switch tab {
            case .colour:
                LumiCategoryTabs(items: categories.map { ($0, LocalizedStringKey($0)) }, selection: $category)
                LumiSwatchRow(colors: HairRetouch.swatches.filter { $0.category == category }.map { ($0.name, $0.color) }, selected: model.draft.hair.dye.strength > 0 ? model.draft.hair.dye.color : nil) { c in
                    model.edit { var h = $0.hair; h.dye.color = c; h.dye.strength = max(h.dye.strength, 0.8); $0.hair = h }
                }
                slider("Amount", \.hair.dye.strength, 0...1)
                slider("Keep shine", \.hair.dye.keepShine, 0...1)
                slider("Roots", \.hair.rootRetouch, 0...1)
                HStack(spacing: 8) {
                    LumiChip(title: "De-oil", selected: model.draft.hair.deOil > 0) { model.edit { var h = $0.hair; h.deOil = h.deOil > 0 ? 0 : 0.6; $0.hair = h } }
                    LumiChip(title: "Smooth", selected: model.draft.hair.smooth > 0) { model.edit { var h = $0.hair; h.smooth = h.smooth > 0 ? 0 : 0.5; $0.hair = h } }
                    Spacer()
                    LumiChip(title: "Off", symbol: "xmark") { model.edit { $0.hair = HairRetouch() } }
                }
            case .shape:
                slider("Crown lift", \.hair.volume, -1...1); slider("Hairline", \.hair.hairline, -1...1); slider("Glow", \.hair.glow, 0...1); slider("Flyaways", \.hair.flyaway, 0...1)
                LumiToggleRow(title: "Keep background straight", subtitle: nil, isOn: .constant(true)).disabled(true).opacity(0.6)
            case .brush:
                LumiToggleRow(title: "Brush the hair area", subtitle: "Add what was missed, erase what is not hair, fill thin spots", isOn: $model.hairBrushActive)
                LumiSegmented(items: [(HairBrushMode.add, LocalizedStringKey("Add")), (HairBrushMode.erase, LocalizedStringKey("Erase")), (HairBrushMode.fill, LocalizedStringKey("Fill"))], selection: $model.hairBrushMode, height: 40)
                if model.draft.hair.add != nil || model.draft.hair.remove != nil { LumiChip(title: "Reset brush edits", symbol: "arrow.counterclockwise") { model.edit { var h = $0.hair; h.add = nil; h.remove = nil; h.fill = nil; $0.hair = h }; model.refreshHairOverlay() } }
            }
        }
        .onAppear { model.refreshHairOverlay() }
        .onChange(of: model.draft.hair.add) { _, _ in model.refreshHairOverlay() }
        .onChange(of: model.draft.hair.remove) { _, _ in model.refreshHairOverlay() }
    }

    private func slider(_ title: String, _ path: WritableKeyPath<EditDocument, Double>, _ range: ClosedRange<Double>) -> some View {
        LumiSliderRow(title: LocalizedStringKey(title), value: Binding(get: { model.draft[keyPath: path] }, set: { model.draft[keyPath: path] = $0 }), range: range,
                      onEnd: { model.commit() })
    }
}

/// The hair mask, tinted, while a hair slider moves or the brush is on: it shows what the edit will touch.
struct HairMaskOverlay: View {
    let image: CGImage?
    let visible: Bool
    let imageSize: CGSize
    var body: some View {
        GeometryReader { geo in
            let d = FitMapping(view: geo.size, image: imageSize).displayed
            if let image, visible {
                Image(decorative: image, scale: 1).resizable().frame(width: d.width, height: d.height).position(x: d.midX, y: d.midY).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: visible).allowsHitTesting(false).accessibilityHidden(true)
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
            Text("Paint over what to hide. It is covered with the area at the offset.").font(.footnote).foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            slider("Source ←→", \.offsetX, -0.5...0.5)
            slider("Source ↑↓", \.offsetY, -0.5...0.5)
            slider("Noise reduction", \.denoise, 0...1)
            HStack { LumiChip(title: "Clear clone", symbol: "xmark") { model.edit { var c = $0.clean; c.cloneMask = nil; $0.clean = c } }; Spacer() }
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


/// Adds room around the photo and fills it in (the fill is the on-device inpainting model).
struct ExpandPanel: View {
    @Bindable var model: EditorModel
    @State private var ratio = "Free"
    private static let ratios: [(String, Double?)] = [("Free", nil), ("1:1", 1), ("4:5", 0.8), ("16:9", 16.0 / 9), ("9:16", 9.0 / 16), ("3:2", 1.5)]

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(Self.ratios, id: \.0) { r in LumiChip(title: LocalizedStringKey(r.0), selected: ratio == r.0) { pick(r) } } }
            }
            slider("Left", \.left); slider("Right", \.right); slider("Top", \.top); slider("Bottom", \.bottom)
            HStack {
                Text(LaMaInpainter.isModelAvailable ? "Works best on scenery and plain backgrounds." : "Install the removal model in Settings to fill the new space.").font(.footnote).foregroundStyle(LumiColor.textSecondary)
                Spacer()
                if !model.draft.expand.isIdentity { LumiChip(title: "Reset", symbol: "arrow.counterclockwise") { ratio = "Free"; model.edit { $0.expand = ExpandConfig() } } }
            }
        }
    }

    private func pick(_ r: (String, Double?)) {
        ratio = r.0
        guard let target = r.1, let o = model.original else { model.edit { $0.expand = ExpandConfig() }; return }
        model.edit { $0.expand = ExpandConfig.toAspect(target, from: o.extent.size) }
    }

    private func slider(_ title: String, _ path: WritableKeyPath<ExpandConfig, Double>) -> some View {
        LumiSliderRow(title: LocalizedStringKey(title), value: Binding(get: { model.draft.expand[keyPath: path] }, set: { model.draft.expand[keyPath: path] = $0; ratio = "Free" }), range: 0...1, onEnd: { model.commit() })
    }
}
