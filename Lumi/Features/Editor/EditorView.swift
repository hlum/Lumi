import PhotosUI
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case adjust = "Adjust", crop = "Crop", text = "Text", remove = "Remove", cutout = "Cutout", filter = "Filter"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .adjust: "slider.horizontal.3"; case .crop: "crop.rotate"; case .text: "textformat"; case .remove: "eraser"; case .cutout: "person.crop.rectangle"; case .filter: "camera.filters" }
    }
}

struct EditorView: View {
    @State private var model = EditorModel()
    @State private var item: PhotosPickerItem?
    @State private var loadFailed = false
    @State private var tool = EditorTool.adjust

    var body: some View {
        VStack(spacing: 0) {
            if model.preview != nil {
                MetalPreviewView(image: model.preview)
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { PhotosPicker("Photo", selection: $item, matching: .images) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.canRedo)
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
        .alert("Couldn't open that photo", isPresented: $loadFailed) {}
        .alert("Couldn't save", isPresented: .constant(model.saveError != nil)) {}
    }
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
