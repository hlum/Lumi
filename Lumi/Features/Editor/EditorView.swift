import PhotosUI
import SwiftData
import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case adjust = "Adjust", crop = "Crop", text = "Text", remove = "Remove", cutout = "Cutout", filter = "Filter", sticker = "Sticker", frame = "Frame", doodle = "Doodle", mark = "Mark", liquify = "Liquify", face = "Face", color = "Color", enhance = "Enhance", export = "Export"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .adjust: "slider.horizontal.3"; case .crop: "crop.rotate"; case .text: "textformat"; case .remove: "eraser"; case .cutout: "person.crop.rectangle"; case .filter: "camera.filters"; case .sticker: "face.smiling"; case .frame: "photo.artframe"; case .doodle: "scribble"; case .color: "paintpalette"; case .face: "face.smiling.inverse"; case .liquify: "hand.draw"; case .mark: "checkmark.seal"; case .enhance: "arrow.up.left.and.arrow.down.right"; case .export: "square.and.arrow.up.on.square" }
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
                    .overlay { if tool == .liquify, let o = model.original { LiquifyOverlay(model: model, imageSize: o.extent.size) } }
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
                    case .mark: MarkPanel(model: model)
                    case .liquify: LiquifyPanel(model: model)
                    case .face: FacePanel(model: model)
                    case .color: ColorPanel(model: model)
                    case .enhance: EnhancePanel(model: model)
                    case .export: ExportPanel(model: model)
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
                Button("Auto", systemImage: "level") { if let o = model.original, let a = AutoStraighten.angle(for: Renderer.proxy(o, maxDimension: 1024)) { model.edit { $0.crop.angle = a } } }
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
                    model.edit { d in var s = d.layers; try? s.add(layer); d.layers = s }   // the stack rejects empty text
                    text = ""
                }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(TextStylePresets.all) { p in
                        Button(LocalizedStringKey(p.name)) { font = p.style.fontName; preset = p }.buttonStyle(.bordered).tint(preset == p ? .accentColor : .secondary)
                    }
                }.padding(.horizontal)
            }
            Toggle("Behind subject", isOn: $behind).padding(.horizontal)
            List {
                ForEach(model.draft.layers.layers) { l in
                    if case .text(let s, _) = l.content {
                        HStack {
                            Text(s)
                            Spacer()
                            Menu("Style") { ForEach(TextStylePresets.all) { p in Button(LocalizedStringKey(p.name)) { let id = l.id; model.edit { d in var st = d.layers; st.update(id) { $0 = TextStylePresets.apply(p, to: $0) }; d.layers = st } } } }
                        }
                    }
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

struct ExportPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 10) {
            Picker("Format", selection: $model.exportSettings.format) { ForEach(ImageFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) } }.pickerStyle(.segmented).padding(.horizontal)
            if model.exportSettings.format != .png {
                HStack { Text("Quality").font(.caption); Slider(value: $model.exportSettings.quality, in: 0.3...1) }.padding(.horizontal)
            }
            Picker("Max size", selection: Binding(get: { model.exportSettings.maxLongSide ?? 0 }, set: { model.exportSettings.maxLongSide = $0 == 0 ? nil : $0 })) {
                Text("Original").tag(0); Text("4096").tag(4096); Text("2048").tag(2048); Text("1080").tag(1080)
            }.pickerStyle(.segmented).padding(.horizontal)
            HStack {
                Text("Print").font(.caption)
                Button("10×15 cm") { model.applyPrintSize(width: 10, height: 15, unit: .cm, dpi: 300) }.buttonStyle(.bordered)
                Button("A4") { model.applyPrintSize(width: 210, height: 297, unit: .mm, dpi: 300) }.buttonStyle(.bordered)
                Button("Off") { model.clearPrintSize() }.buttonStyle(.bordered)
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
                            Button(name.capitalized) { let c = ColorGrade.curvePresets[name]!; model.edit { $0.grade.rgbCurve = c.rgb; $0.grade.redCurve = c.r; $0.grade.greenCurve = c.g; $0.grade.blueCurve = c.b } }.buttonStyle(.bordered)
                        }
                        Button("Reset") { model.edit { $0.grade.rgbCurve = ToneCurve(); $0.grade.redCurve = ToneCurve(); $0.grade.greenCurve = ToneCurve(); $0.grade.blueCurve = ToneCurve() }; shadows = 0; mids = 0; highs = 0 }.buttonStyle(.bordered)
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
        HStack {
            Text(LocalizedStringKey(title)).font(.caption).frame(width: 90, alignment: .leading)
            Slider(value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; apply?() }), in: range) { if !$0 { model.commit() } }
        }.padding(.horizontal)
    }
}

struct FacePanel: View {
    enum Group: String, CaseIterable { case looks = "Looks", skin = "Skin", shape = "Shape", makeup = "Makeup", detail = "Detail" }
    @Bindable var model: EditorModel
    @State private var group = Group.looks
    @State private var strength = 1.0
    @State private var lookID = AutoBeauty.looks[0].id

    var body: some View {
        VStack(spacing: 4) {
            Picker("Group", selection: $group) { ForEach(Group.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }.pickerStyle(.segmented).padding(.horizontal)
            ScrollView {
                VStack(spacing: 2) {
                    switch group {
                    case .looks:
                        HStack {
                            ForEach(AutoBeauty.looks) { l in Button(LocalizedStringKey(l.name)) { lookID = l.id; apply() }.buttonStyle(.bordered).tint(lookID == l.id ? .accentColor : .secondary) }
                            Button("Off") { model.edit { $0.face = FaceRetouch() } }.buttonStyle(.bordered)
                        }
                        row("Strength", $strength, 0...1) { apply() }
                    case .skin:
                        row("Smooth", f(\.skin.smooth), 0...1); row("Texture", f(\.skin.texture), 0...1); row("Whiten", f(\.skin.whiten), 0...1); row("Rosy", f(\.skin.rosy), 0...1); row("Tan", f(\.skin.tan), 0...1)
                    case .shape:
                        row("Jaw", f(\.reshape.jawSlim)); row("Face width", f(\.reshape.faceWidth)); row("Chin", f(\.reshape.chinLength)); row("Eyes", f(\.reshape.eyeSize)); row("Nose", f(\.reshape.noseSlim)); row("Mouth", f(\.reshape.mouthSize)); row("Cheek volume", f(\.reshape.cheekVolume)); row("Lift", f(\.reshape.lift))
                    case .makeup:
                        row("Lipstick", f(\.makeup.lipOpacity), 0...1); row("Blush", f(\.makeup.blushOpacity), 0...1); row("Lip shine", f(\.makeup.ombre), 0...1)
                    case .detail:
                        row("Flash", f(\.detail.flash), 0...1); row("Under-eye", f(\.detail.underEye), 0...1); row("Fine lines", f(\.detail.wrinkles), 0...1); row("Teeth", f(\.detail.teethWhiten), 0...1); row("Bright eyes", f(\.detail.eyeBright), 0...1)
                    }
                }
            }
        }
    }

    private func apply() { if let l = AutoBeauty.looks.first(where: { $0.id == lookID }) { model.edit { $0.face = FaceRetouch.look(l, strength: strength) } } }

    private func f(_ path: WritableKeyPath<FaceRetouch, Double>) -> Binding<Double> {
        Binding(get: { model.draft.face[keyPath: path] }, set: { model.draft.face[keyPath: path] = $0 })
    }

    private func row(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double> = -1...1, onEnd: (() -> Void)? = nil) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).font(.caption).frame(width: 84, alignment: .leading)
            Slider(value: value, in: range) { if !$0 { if let onEnd { onEnd() } else { model.commit() } } }
        }.padding(.horizontal)
    }
}

struct LiquifyPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 8) {
            Picker("Brush", selection: Binding(get: { model.warpBrush.kind }, set: { model.warpBrush.kind = $0 })) {
                Text("Slim").tag(BrushStroke.Kind.push); Text("Zoom in").tag(BrushStroke.Kind.bloat); Text("Zoom out").tag(BrushStroke.Kind.pinch)
            }.pickerStyle(.segmented).padding(.horizontal)
            HStack { Text("Size").font(.caption); Slider(value: Binding(get: { model.warpBrush.size }, set: { model.warpBrush.size = $0 }), in: 0.03...0.3) }.padding(.horizontal)
            HStack { Text("Strength").font(.caption); Slider(value: Binding(get: { model.warpBrush.strength }, set: { model.warpBrush.strength = $0 }), in: 0.1...1) }.padding(.horizontal)
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
                Button("Apply") { model.edit { $0.watermark = text.isEmpty ? nil : current } }.buttonStyle(.borderedProminent)
                Button("Save", systemImage: "star") { if !text.isEmpty { box.save(current) } }.labelStyle(.iconOnly).buttonStyle(.bordered)
                Button("Off") { model.edit { $0.watermark = nil } }.buttonStyle(.bordered)
            }.padding(.horizontal)
            HStack {
                ForEach(TimeStampStyle.allCases, id: \.self) { st in
                    Button(st.rawValue.capitalized) { text = WatermarkMath.timeStamp(.now, style: st) }.buttonStyle(.bordered)
                }
                Toggle("Tiled", isOn: $tiled).fixedSize()
            }.padding(.horizontal)
            HStack { Text("Opacity").font(.caption); Slider(value: $opacity, in: 0.1...1) }.padding(.horizontal)
            HStack { Text("Size").font(.caption); Slider(value: $size, in: 0.03...0.2) }.padding(.horizontal)
            if !box.library.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(box.library.items) { w in
                            Button(w.name) { if case .text(let t) = w.kind { text = t }; tiled = w.isTiled; opacity = w.opacity; size = w.size; model.edit { $0.watermark = w } }
                                .buttonStyle(.bordered).contextMenu { Button("Delete", role: .destructive) { box.delete(w.id) } }
                        }
                    }.padding(.horizontal)
                }
            }
        }
    }
}
