import PhotosUI
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case adjust = "Adjust", crop = "Crop", text = "Text", remove = "Remove"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .adjust: "slider.horizontal.3"; case .crop: "crop.rotate"; case .text: "textformat"; case .remove: "eraser" }
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

    var body: some View {
        VStack {
            HStack {
                TextField("Add text", text: $text).textFieldStyle(.roundedBorder)
                Button("Add") {
                    let layer = Layer(content: .text(text, TextStyle()))
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
