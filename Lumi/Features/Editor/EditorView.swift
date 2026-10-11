import PhotosUI
import SwiftData
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case adjust = "Adjust", crop = "Crop", text = "Text", remove = "Remove", cutout = "Cutout", filter = "Filter", sticker = "Sticker", frame = "Frame", doodle = "Doodle", enhance = "Enhance"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .adjust: "slider.horizontal.3"; case .crop: "crop.rotate"; case .text: "textformat"; case .remove: "eraser"; case .cutout: "person.crop.rectangle"; case .filter: "camera.filters"; case .sticker: "face.smiling"; case .frame: "photo.artframe"; case .doodle: "scribble"; case .enhance: "arrow.up.left.and.arrow.down.right" }
    }
}

struct EditorView: View {
    @Environment(\.modelContext) private var context
    /// Pass a project to reopen its draft.
    var project: Project?
    @State private var model = EditorModel()
    @State private var item: PhotosPickerItem?
    @State private var loadFailed = false
    @State private var tool = EditorTool.adjust
    @State private var library = RecipeLibrary()
    @State private var recipeSaved = false

    var body: some View {
        VStack(spacing: 0) {
            if model.preview != nil {
                MetalPreviewView(image: model.preview)
                    .overlay { if tool == .doodle, let o = model.original { DoodleOverlay(model: model, imageSize: o.extent.size) } }
                    .overlay { if tool == .remove, let r = model.remover, let o = model.original { RemoverOverlay(remover: r, imageSize: o.extent.size) } }
                    .onLongPressGesture(minimumDuration: 0.1, pressing: { model.showOriginal = $0 }, perform: {})
                Group {
                    switch tool {
                    case .adjust: AdjustPanel(model: model)
                    case .crop: CropPanel(model: model)
                    case .text: TextPanel(model: model)
                    case .remove: RemoverPanel(editor: model)
                    case .cutout: CutoutPanel(model: model)
                    case .filter: FilterPanel(model: model)
                    case .sticker: StickerPanel(model: model)
                    case .frame: FramePanel(model: model)
                    case .doodle: DoodlePanel(model: model)
                    case .enhance: EnhancePanel(model: model)
                    }
                }
                .frame(maxHeight: 220)
                Picker("Tool", selection: $tool) {
                    ForEach(EditorTool.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented).padding()
            } else {
                ContentUnavailableView("Pick a photo", systemImage: "photo")
            }
        }
        .navigationTitle("Editor")
        .task {
            let store = ProjectStore(context: context, directory: ProjectStore.defaultDirectory)
            model.session = ProjectSession(store: store, project: project)
            if project != nil { try? model.openDraft() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { PhotosPicker("Photo", selection: $item, matching: .images) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.canRedo)
                Button("Save recipe", systemImage: "wand.and.stars.inverse") { saveRecipe() }.disabled(model.original == nil || model.draft.operations.isEmpty)
                Button("Save", systemImage: "square.and.arrow.down") { Task { await model.save() } }.disabled(model.original == nil)
            }
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self), (try? model.load(data: data)) != nil { loadFailed = false }
                else { loadFailed = true }
            }
        }
        .alert("Recipe saved", isPresented: $recipeSaved) {}
        .alert("Couldn't open that photo", isPresented: $loadFailed) {}
        .alert("Couldn't save", isPresented: .constant(model.saveError != nil)) {}
    }
}

extension EditorView {
    func saveRecipe() { if library.save(name: "", from: model.draft) != nil { recipeSaved = true } }
}

struct AdjustPanel: View {
    @Bindable var model: EditorModel
    @State private var key = AdjustParams.Key.brightness

    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(AdjustParams.presets.keys.sorted(), id: \.self) { name in
                        Button(name.capitalized) { model.edit { $0.adjust = AdjustParams.presets[name]! } }.buttonStyle(.bordered)
                    }
                }.padding(.horizontal)
            }
            Picker("Setting", selection: $key) { ForEach(AdjustParams.Key.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                .pickerStyle(.menu)
            HStack {
                Slider(value: Binding(get: { model.draft.adjust[key] }, set: { model.draft.adjust[key] = $0 }),
                       in: key.range) { editing in if !editing { model.commit() } }
                Button("Reset", systemImage: "arrow.counterclockwise") { model.edit { $0.adjust.reset(key) } }
                    .labelStyle(.iconOnly).disabled(model.draft.adjust[key] == 0)
            }.padding(.horizontal)
        }
    }
}

struct CropPanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack {
            HStack {
                Button("Rotate", systemImage: "rotate.right") { model.edit { $0.crop.quarterTurns = ($0.crop.quarterTurns + 1) % 4 } }
                Button("Flip H", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { model.edit { $0.crop.flipH.toggle() } }
                Button("Flip V", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") { model.edit { $0.crop.flipV.toggle() } }
                Button("Reset", systemImage: "arrow.counterclockwise") { model.edit { $0.crop = CropSpec() } }
            }.labelStyle(.iconOnly).buttonStyle(.bordered)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(CropSpec.ratios, id: \.name) { r in
                        Button(r.name) {
                            guard let o = model.original else { return }
                            model.edit { $0.crop.rect = CropSpec.rect(aspect: r.w, r.h, in: o.extent.size) }
                        }.buttonStyle(.bordered)
                    }
                }.padding(.horizontal)
            }
            HStack {
                Text("Angle")
                Slider(value: Binding(get: { model.draft.crop.angle }, set: { model.draft.crop.angle = $0 }), in: -45...45) { editing in
                    if !editing { model.commit() }
                }
            }.padding(.horizontal)
        }
    }
}

struct TextPanel: View {
    @Bindable var model: EditorModel
    @State private var text = ""
    @State private var font = FontLibrary.all.first!.postScript

    var body: some View {
        VStack {
            Picker("Font", selection: $font) { ForEach(FontLibrary.all) { Text($0.name).tag($0.postScript) } }.pickerStyle(.menu)
            HStack {
                TextField("Add text", text: $text).textFieldStyle(.roundedBorder)
                Button("Add") {
                    var style = TextStyle(); style.fontName = font
                    let layer = Layer(content: .text(text, style))
                    model.edit { d in var s = d.layers; try? s.add(layer); d.layers = s }   // the stack rejects empty text
                    text = ""
                }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.horizontal)
            List {
                ForEach(model.draft.layers.layers) { l in
                    if case .text(let s, _) = l.content { Text(s) }
                }
                .onDelete { idx in
                    let ids = idx.map { model.draft.layers.layers[$0].id }
                    model.edit { d in var s = d.layers; ids.forEach { s.remove($0) }; d.layers = s }
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
                    Button("Off") { model.edit { $0.cutout = nil } }.buttonStyle(.bordered)
                    ForEach(choices, id: \.0) { name, bg in
                        Button(name) { model.edit { var c = $0.cutout ?? CutoutConfig(); c.background = bg; $0.cutout = c } }.buttonStyle(.bordered)
                    }
                }.padding(.horizontal)
            }
            slider("Soft edge", \.feather, 0...1)
            slider("Edge shift", \.shift, -1...1)
        }
    }

    private func slider(_ title: String, _ path: WritableKeyPath<CutoutConfig, Double>, _ range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(.caption).frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: { config[keyPath: path] }, set: { v in var c = config; c[keyPath: path] = v; model.draft.cutout = c }), in: range) { editing in
                if !editing { model.commit() }
            }
        }.padding(.horizontal).disabled(model.draft.cutout == nil)
    }
}

struct FilterPanel: View {
    @Bindable var model: EditorModel
    @State private var category = FilterLibrary.shared.categories.first ?? ""
    private let library = FilterLibrary.shared

    var body: some View {
        VStack {
            Picker("Category", selection: $category) { ForEach(library.categories, id: \.self) { Text($0.capitalized).tag($0) } }.pickerStyle(.menu)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Off") { model.edit { $0.filter = nil } }.buttonStyle(.bordered)
                    ForEach(library.entries(in: category)) { e in
                        Button(LocalizedStringKey(e.name)) { model.edit { $0.filter = (e.id, model.draft.filter?.intensity ?? 1) } }
                            .buttonStyle(.bordered).tint(model.draft.filter?.id == e.id ? .accentColor : .secondary)
                    }
                }.padding(.horizontal)
            }
            Slider(value: Binding(get: { model.draft.filter?.intensity ?? 1 }, set: { v in if let f = model.draft.filter { model.draft.filter = (f.id, v) } }), in: 0...1) { editing in
                if !editing { model.commit() }
            }.padding(.horizontal).disabled(model.draft.filter == nil)
        }
    }
}

struct StickerPanel: View {
    @Bindable var model: EditorModel
    @State private var query = ""
    @State private var outline = 0.0

    var body: some View {
        VStack {
            TextField("Search", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal)
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
            HStack {
                Text("Outline").font(.caption)
                Slider(value: $outline, in: 0...0.05)
            }.padding(.horizontal)
        }
    }

    private func add(_ id: String) {
        let layer = Layer(content: .sticker(id: id, outline: outline))
        model.edit { d in var s = d.layers; try? s.add(layer); d.layers = s }
    }
}

struct FramePanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack {
            Picker("Style", selection: Binding(get: { model.draft.frame.style }, set: { v in model.edit { var f = $0.frame; f.style = v; if f.padding == 0 { f.padding = 0.04 }; $0.frame = f } })) {
                ForEach(FrameConfig.Style.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal)
            HStack {
                Text("Padding").font(.caption)
                Slider(value: Binding(get: { model.draft.frame.padding }, set: { model.draft.frame.padding = $0 }), in: 0...0.25) { if !$0 { model.commit() } }
            }.padding(.horizontal)
            HStack {
                ForEach([("White", RGBA.white), ("Black", RGBA.black), ("Cream", RGBA(r: 1, g: 0.95, b: 0.8, a: 1))], id: \.0) { name, c in
                    Button(name) { model.edit { var f = $0.frame; f.color = c; $0.frame = f } }.buttonStyle(.bordered)
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
                    Button(n) { model.doodleColor = c }.buttonStyle(.bordered)
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
                    Button("Off") { model.edit { $0.upscale = nil } }.buttonStyle(.bordered)
                    Button("2×") { model.edit { $0.upscale = 2 } }.buttonStyle(.bordered).tint(model.draft.upscale == 2 ? .accentColor : .secondary)
                    Button("4×") { model.edit { $0.upscale = 4 } }.buttonStyle(.bordered).tint(model.draft.upscale == 4 ? .accentColor : .secondary)
                }
            } else {
                Text("Enhance works on photos up to 2048 px on the long side.").font(.caption).foregroundStyle(.secondary).padding()
            }
            if Renderer.services.colorizer != nil, let o = model.original, max(o.extent.width, o.extent.height) <= CGFloat(SiggraphColorizer.maxInputSide) {
                HStack {
                    Text("Colorize").font(.caption)
                    Button("Off") { model.edit { $0.colorize = nil } }.buttonStyle(.bordered)
                    Button("50%") { model.edit { $0.colorize = 0.5 } }.buttonStyle(.bordered)
                    Button("100%") { model.edit { $0.colorize = 1 } }.buttonStyle(.bordered)
                }
            }
            if let o = model.original {
                Button("Restore old photo", systemImage: "wand.and.stars") {
                    let plan = OldPhotoRestore.plan(for: o, canUpscale: model.canUpscale, canColorize: Renderer.services.colorizer != nil)
                    model.edit { $0 = OldPhotoRestore.apply(plan, to: $0) }
                }.buttonStyle(.borderedProminent)
            }
        }
    }
}
