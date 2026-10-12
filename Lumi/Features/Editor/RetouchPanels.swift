import CoreImage
import PhotosUI
import SwiftUI

/// One adjustable value of the face edit: chip title, where it lives, and what to outline while it moves.
struct FaceSlider: Identifiable {
    var id: String { title }
    var title: String
    var path: WritableKeyPath<FaceRetouch, Double>
    var range: ClosedRange<Double> = -1...1
    var mark: FaceMark?
}

/// Chips for a list of values and one big slider for the chosen chip, as in the design's retouch screens.
struct FaceSliderGroup: View {
    @Bindable var model: EditorModel
    var items: [FaceSlider]
    @State private var selectedID: String?

    private var selected: FaceSlider { items.first { $0.id == selectedID } ?? items[0] }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        LumiChip(title: LocalizedStringKey(item.title), selected: item.id == selected.id, edited: model.draft.face[keyPath: item.path] != 0) { selectedID = item.id }
                    }
                }
            }
            let s = selected
            LumiSliderRow(title: LocalizedStringKey(s.title), value: Binding(get: { model.draft.face[keyPath: s.path] }, set: { model.draft.face[keyPath: s.path] = $0 }),
                          range: s.range, onEditing: { if let m = s.mark { model.mark(m, editing: $0) } }, onEnd: { model.commit() })
            .id(s.id)
        }
        .onChange(of: items.map(\.id)) { _, _ in selectedID = nil }
    }
}

// MARK: Reshape

struct ReshapePanel: View {
    enum Tab: String, CaseIterable { case face = "Face", eyes = "Eyes", nose = "Nose", mouth = "Mouth", brows = "Brows", balance = "Balance", shade = "3D" }
    @Bindable var model: EditorModel
    @State private var tab = Tab.face

    static func items(_ t: Tab) -> [FaceSlider] {
        switch t {
        case .face: [FaceSlider(title: "Chin", path: \.reshape.chinLength, mark: .chin), FaceSlider(title: "Jawline", path: \.reshape.jawSlim, mark: .jaw),
                     FaceSlider(title: "V shape", path: \.shape.vShape, mark: .jaw), FaceSlider(title: "Width", path: \.reshape.faceWidth, mark: .faceWidth),
                     FaceSlider(title: "Cheekbones", path: \.shape.cheekbones, mark: .cheeks), FaceSlider(title: "Cheek volume", path: \.reshape.cheekVolume, mark: .cheeks),
                     FaceSlider(title: "Lift", path: \.reshape.lift, mark: .lift), FaceSlider(title: "Forehead", path: \.shape.forehead, mark: .face)]
        case .eyes: [FaceSlider(title: "Size", path: \.reshape.eyeSize, mark: .eyes), FaceSlider(title: "Distance", path: \.shape.eyeDistance, mark: .eyes),
                     FaceSlider(title: "Height", path: \.shape.eyeHeight, mark: .eyes), FaceSlider(title: "Tilt", path: \.shape.eyeTilt, mark: .eyes),
                     FaceSlider(title: "Inner corner", path: \.shape.eyeInner, mark: .eyes), FaceSlider(title: "Outer corner", path: \.shape.eyeOuter, mark: .eyes),
                     FaceSlider(title: "Eyelids", path: \.shape.eyeLids, mark: .eyes), FaceSlider(title: "Socket", path: \.shape.eyeSocket, mark: .eyes)]
        case .nose: [FaceSlider(title: "Slim", path: \.reshape.noseSlim, mark: .nose), FaceSlider(title: "Wings", path: \.shape.noseWings, mark: .nose),
                     FaceSlider(title: "Bridge", path: \.shape.noseBridge, mark: .nose), FaceSlider(title: "Tip", path: \.shape.noseTip, mark: .nose),
                     FaceSlider(title: "Length", path: \.shape.noseLength, mark: .nose)]
        case .mouth: [FaceSlider(title: "Size", path: \.reshape.mouthSize, mark: .mouth), FaceSlider(title: "Width", path: \.shape.mouthWidth, mark: .mouth),
                      FaceSlider(title: "Fullness", path: \.shape.mouthFullness, mark: .mouth), FaceSlider(title: "Smile", path: \.shape.mouthSmile, mark: .mouth),
                      FaceSlider(title: "Cupid's bow", path: \.shape.mouthCupid, mark: .mouth), FaceSlider(title: "Protrusion", path: \.shape.mouthProtrusion, mark: .mouth),
                      FaceSlider(title: "Pout", path: \.shape.mouthPout, mark: .mouth)]
        case .brows: [FaceSlider(title: "Height", path: \.eyes.browHeight, mark: .brows), FaceSlider(title: "Spacing", path: \.shape.browSpacing, mark: .brows),
                      FaceSlider(title: "Peak", path: \.shape.browPeak, mark: .brows), FaceSlider(title: "Lift", path: \.shape.browLift, mark: .brows)]
        case .balance: [FaceSlider(title: "Move left/right", path: \.ratio.shiftX, mark: .face), FaceSlider(title: "Move up/down", path: \.ratio.shiftY, mark: .face),
                        FaceSlider(title: "Rotate", path: \.ratio.rotate, mark: .face), FaceSlider(title: "Symmetry", path: \.ratio.symmetry, range: 0...1, mark: .face),
                        FaceSlider(title: "Even out jaw", path: \.ratio.unevenFix, range: 0...1, mark: .jaw)]
        case .shade: [FaceSlider(title: "3D shading", path: \.ratio.shade3D, range: 0...1)]
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            LumiCategoryTabs(items: Tab.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $tab)
            FaceSliderGroup(model: model, items: Self.items(tab)).id(tab)
            HStack(spacing: 8) {
                LumiChip(title: "Protect features", selected: model.draft.face.ratio.protectFeatures, symbol: "lock") { model.edit { var f = $0.face; f.ratio.protectFeatures.toggle(); $0.face = f } }
                LumiChip(title: "Lock glasses", selected: model.draft.face.ratio.glassesLock, symbol: "eyeglasses") { model.edit { var f = $0.face; f.ratio.glassesLock.toggle(); $0.face = f } }
                Spacer()
                LumiChip(title: "Reset", symbol: "arrow.counterclockwise") { model.edit { var f = $0.face; f.reshape = FaceReshapeParams(); f.shape = FeatureShape(); f.ratio = FaceRatio(); f.eyes.browHeight = 0; $0.face = f } }
            }
        }
    }
}

// MARK: shared colour sets

enum LumiPalette {
    static let lips: [(name: String, color: RGBA)] = [
        ("Nude", RGBA(r: 0.78, g: 0.5, b: 0.45, a: 1)), ("Rose", RGBA(r: 0.85, g: 0.35, b: 0.45, a: 1)), ("Coral", RGBA(r: 1, g: 0.4, b: 0.35, a: 1)),
        ("Red", RGBA(r: 0.8, g: 0.05, b: 0.1, a: 1)), ("Berry", RGBA(r: 0.6, g: 0.12, b: 0.3, a: 1)), ("Plum", RGBA(r: 0.45, g: 0.1, b: 0.3, a: 1)), ("Mauve", RGBA(r: 0.65, g: 0.4, b: 0.5, a: 1)),
    ]
    static let blush: [(name: String, color: RGBA)] = [
        ("Peach", RGBA(r: 1, g: 0.6, b: 0.45, a: 1)), ("Pink", RGBA(r: 0.95, g: 0.5, b: 0.55, a: 1)), ("Rose", RGBA(r: 0.85, g: 0.4, b: 0.5, a: 1)), ("Coral", RGBA(r: 1, g: 0.5, b: 0.4, a: 1)), ("Berry", RGBA(r: 0.75, g: 0.3, b: 0.45, a: 1)),
    ]
    static let shadow: [(name: String, color: RGBA)] = [
        ("Taupe", RGBA(r: 0.55, g: 0.45, b: 0.42, a: 1)), ("Rose", RGBA(r: 0.85, g: 0.55, b: 0.6, a: 1)), ("Peach", RGBA(r: 0.95, g: 0.7, b: 0.55, a: 1)), ("Plum", RGBA(r: 0.45, g: 0.25, b: 0.45, a: 1)),
        ("Copper", RGBA(r: 0.75, g: 0.45, b: 0.3, a: 1)), ("Smoke", RGBA(r: 0.3, g: 0.3, b: 0.35, a: 1)), ("Blue", RGBA(r: 0.35, g: 0.45, b: 0.7, a: 1)),
    ]
    static let brows: [(name: String, color: RGBA)] = [
        ("Black", RGBA(r: 0.1, g: 0.08, b: 0.08, a: 1)), ("Dark brown", RGBA(r: 0.25, g: 0.15, b: 0.1, a: 1)), ("Brown", RGBA(r: 0.4, g: 0.27, b: 0.18, a: 1)), ("Blonde", RGBA(r: 0.65, g: 0.5, b: 0.3, a: 1)),
    ]
    static let lens: [(name: String, color: RGBA)] = [
        ("Hazel", RGBA(r: 0.55, g: 0.42, b: 0.25, a: 1)), ("Gray", RGBA(r: 0.55, g: 0.58, b: 0.62, a: 1)), ("Brown", RGBA(r: 0.42, g: 0.29, b: 0.18, a: 1)), ("Blue", RGBA(r: 0.42, g: 0.56, b: 0.72, a: 1)), ("Green", RGBA(r: 0.43, g: 0.6, b: 0.45, a: 1)),
    ]
    static let nails: [(name: String, color: RGBA)] = [
        ("Cherry", RGBA(r: 0.8, g: 0.1, b: 0.2, a: 1)), ("Rose", RGBA(r: 0.9, g: 0.5, b: 0.6, a: 1)), ("Nude", RGBA(r: 0.9, g: 0.7, b: 0.62, a: 1)), ("Plum", RGBA(r: 0.45, g: 0.15, b: 0.35, a: 1)),
        ("Navy", RGBA(r: 0.1, g: 0.15, b: 0.35, a: 1)), ("Mint", RGBA(r: 0.6, g: 0.85, b: 0.75, a: 1)), ("White", RGBA(r: 0.98, g: 0.98, b: 0.98, a: 1)), ("Black", RGBA(r: 0.07, g: 0.07, b: 0.08, a: 1)),
    ]
}

// MARK: Auto beauty

struct AutoBeautyPanel: View {
    @Bindable var model: EditorModel
    @State private var group = "For you"
    @State private var lookID: String?
    @State private var amount = 0.65

    var body: some View {
        VStack(spacing: 12) {
            LumiCategoryTabs(items: AutoBeauty.groups.map { ($0, LocalizedStringKey($0)) }, selection: $group)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    LumiToolCircle(symbol: "xmark", value: nil, title: "Off", selected: lookID == nil) { lookID = nil; model.edit { var f = $0.face; f.skin = SkinParams(); f.reshape = FaceReshapeParams(); f.makeup = MakeupParams(); $0.face = f } }
                    ForEach(AutoBeauty.looks(in: group)) { l in
                        LumiToolCircle(symbol: "sparkles", value: nil, title: LocalizedStringKey(l.name), selected: lookID == l.id) { lookID = l.id; apply() }
                    }
                }
            }
            LumiSliderRow(title: "Amount", value: $amount, range: 0...1, defaultValue: 0.65, onEditing: { _ in }, onEnd: { apply() })
                .disabled(lookID == nil).opacity(lookID == nil ? 0.5 : 1)
        }
    }

    private func apply() {
        guard let l = AutoBeauty.looks.first(where: { $0.id == lookID }) else { return }
        let s = AutoBeauty.scaled(l, strength: amount)
        model.edit { var f = $0.face; f.skin = s.skin; f.reshape = s.face; f.makeup = s.makeup; $0.face = f }
    }
}

// MARK: Skin

struct SkinPanel: View {
    @Bindable var model: EditorModel
    /// Appearance changes: no outline on the photo, the change itself is what the user watches.
    static let items: [FaceSlider] = [
        FaceSlider(title: "Smooth", path: \.skin.smooth, range: 0...1), FaceSlider(title: "Even out", path: \.skin.even, range: 0...1),
        FaceSlider(title: "Matte", path: \.skin.matte, range: 0...1), FaceSlider(title: "Glow", path: \.skin.glow, range: 0...1),
        FaceSlider(title: "Texture", path: \.skin.texture, range: 0...1), FaceSlider(title: "Whiten", path: \.skin.whiten, range: 0...1),
    ]
    static let tones: [(String, Double, Double, Double)] = [("Natural", 0, 0, 0), ("Rosy", 0, 0.5, 0), ("Warm", 0, 0, 0.35), ("Bright", 0.5, 0, 0)]
    @State private var showTone = false

    var body: some View {
        VStack(spacing: 12) {
            FaceSliderGroup(model: model, items: Self.items)
            Text("Tone").font(LumiFont.caption()).foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) {
                ForEach(Self.tones, id: \.0) { t in
                    let on = model.draft.face.skin.whiten == t.1 && model.draft.face.skin.rosy == t.2 && model.draft.face.skin.tan == t.3
                    Button { model.edit { var f = $0.face; f.skin.whiten = t.1; f.skin.rosy = t.2; f.skin.tan = t.3; $0.face = f } } label: {
                        VStack(spacing: 4) {
                            Circle().fill(Color(red: 0.91 - t.3 * 0.1 + t.1 * 0.05, green: 0.76 - t.3 * 0.2 + t.1 * 0.07 - t.2 * 0.05, blue: 0.66 - t.3 * 0.2 + t.1 * 0.07)).frame(width: 40, height: 40)
                                .padding(3).overlay(Circle().strokeBorder(on ? LumiColor.selectedPill : .clear, lineWidth: 2))
                            Text(LocalizedStringKey(t.0)).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(LumiColor.text)
                        }
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }
}

// MARK: Eyes and teeth

struct EyesTeethPanel: View {
    enum Area: String, CaseIterable { case eyes = "Eyes", teeth = "Teeth" }
    @Bindable var model: EditorModel
    static let eyeItems: [FaceSlider] = [
        FaceSlider(title: "Brighten", path: \.detail.eyeBright, range: 0...1), FaceSlider(title: "Contacts", path: \.detail.contactAmount, range: 0...1),
        FaceSlider(title: "Catchlight", path: \.detail.catchlight, range: 0...1), FaceSlider(title: "Eye bags", path: \.detail.eyeBags, range: 0...1),
    ]
    static let teethItems: [FaceSlider] = [FaceSlider(title: "Whiten", path: \.detail.teethWhiten, range: 0...1)]
    @State private var area = Area.eyes

    var body: some View {
        VStack(spacing: 12) {
            LumiSegmented(items: Area.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $area, height: 40)
            switch area {
            case .eyes:
                FaceSliderGroup(model: model, items: Self.eyeItems)
                Text("Lens colour").font(LumiFont.caption()).foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                LumiSwatchRow(colors: LumiPalette.lens, selected: model.draft.face.detail.contactColor) { c in
                    model.edit { var f = $0.face; f.detail.contactColor = c; if f.detail.contactAmount == 0 { f.detail.contactAmount = 0.6 }; $0.face = f }
                }
            case .teeth:
                FaceSliderGroup(model: model, items: Self.teethItems)
            }
        }
    }
}

// MARK: Under-eye and lines

struct UnderEyePanel: View {
    @Bindable var model: EditorModel
    static let items: [FaceSlider] = [
        FaceSlider(title: "Dark circles", path: \.detail.underEye, range: 0...1), FaceSlider(title: "Eye bags", path: \.detail.eyeBags, range: 0...1),
        FaceSlider(title: "Tear troughs", path: \.detail.tearTroughs, range: 0...1), FaceSlider(title: "Smile lines", path: \.detail.smileLines, range: 0...1),
        FaceSlider(title: "Eye lines", path: \.detail.eyeLines, range: 0...1),
    ]
    var body: some View {
        VStack(spacing: 12) {
            FaceSliderGroup(model: model, items: Self.items)
            LumiChip(title: "One-tap smooth", symbol: "wand.and.stars") {
                model.edit { var f = $0.face; f.detail.underEye = 0.6; f.detail.eyeBags = 0.4; f.detail.eyeLines = 0.4; f.detail.smileLines = 0.3; $0.face = f }
            }
        }
    }
}

// MARK: Blemishes

struct BlemishPanel: View {
    enum Mode: String, CaseIterable { case spots = "Spots", concealer = "Concealer", redness = "Redness" }
    @Bindable var model: EditorModel
    @State private var mode = Mode.spots
    @State private var auto = true

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(Mode.allCases, id: \.self) { m in LumiChip(title: LocalizedStringKey(m.rawValue), selected: mode == m) { mode = m } } }
            }
            switch mode {
            case .spots:
                LumiToggleRow(title: "Find spots automatically", subtitle: nil, isOn: Binding(get: { model.draft.face.blemish.spots > 0 }, set: { on in model.edit { var f = $0.face; f.blemish.spots = on ? 0.6 : 0; $0.face = f } }))
                if model.draft.face.blemish.spots > 0 {
                    LumiSliderRow(title: "Sensitivity", value: Binding(get: { model.draft.face.blemish.spots }, set: { model.draft.face.blemish.spots = $0 }), range: 0.1...1, defaultValue: 0.6, onEnd: { model.commit() })
                }
                LumiSliderRow(title: "Tap size", value: $model.blemishTapSize, range: 0.01...0.06, defaultValue: 0.025, onEnd: {})
                HStack {
                    Text(model.draft.face.blemish.manual.isEmpty ? "Tap a spot on the photo to heal it." : "\(model.draft.face.blemish.manual.count) healed by tap").font(.footnote).foregroundStyle(LumiColor.textSecondary)
                    Spacer()
                    if !model.draft.face.blemish.manual.isEmpty { LumiChip(title: "Undo tap", symbol: "arrow.uturn.backward") { model.edit { var f = $0.face; _ = f.blemish.manual.popLast(); $0.face = f } } }
                }
            case .concealer:
                LumiSliderRow(title: "Concealer", value: Binding(get: { model.draft.face.blemish.concealer }, set: { model.draft.face.blemish.concealer = $0 }), range: 0...1, onEnd: { model.commit() })
            case .redness:
                LumiSliderRow(title: "Redness", value: Binding(get: { model.draft.face.blemish.redness }, set: { model.draft.face.blemish.redness = $0 }), range: 0...1, onEnd: { model.commit() })
            }
        }
    }
}

/// Tap a spot to heal it; rings show what was healed.
struct BlemishTapOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            let d = map.displayed
            ZStack {
                ForEach(Array(model.draft.face.blemish.manual.enumerated()), id: \.offset) { _, s in
                    Circle().stroke(LumiColor.accent, lineWidth: 2).frame(width: max(s.r * d.width * 2, 14), height: max(s.r * d.width * 2, 14))
                        .position(x: d.minX + s.x * d.width, y: d.minY + s.y * d.height)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                guard let p = map.toImage(loc), imageSize.width > 0 else { return }
                model.edit { var f = $0.face; f.blemish.manual.append(HealSpot(x: Double(p.x / imageSize.width), y: Double(p.y / imageSize.height), r: model.blemishTapSize)); $0.face = f }
            }
        }
    }
}

// MARK: Body

struct BodyPanel: View {
    enum Tab: String, CaseIterable { case auto = "Auto", legs = "Legs", waist = "Waist", upper = "Upper" }
    @Bindable var model: EditorModel
    @State private var tab = Tab.auto
    @State private var key: BodyReshapeParams.Key = .waist

    private func keys(_ t: Tab) -> [(String, BodyReshapeParams.Key)] {
        switch t {
        case .auto: [("Waist", .waist), ("Legs longer", .legLength), ("Slim legs", .legSlim), ("Hips", .hips), ("Shoulders", .shoulder)]
        case .legs: [("Longer legs", .legLength), ("Slim legs", .legSlim), ("Straighten", .legStraighten), ("Thighs", .thighs), ("Calves", .calves)]
        case .waist: [("Waist", .waist), ("Hips", .hips)]
        case .upper: [("Shoulders", .shoulder), ("Arms", .armSlim), ("Head size", .headSize)]
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            LumiCategoryTabs(items: Tab.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $tab).onChange(of: tab) { _, t in key = keys(t)[0].1 }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(keys(tab), id: \.1) { item in
                        LumiChip(title: LocalizedStringKey(item.0), selected: key == item.1, edited: model.draft.body.params[keyPath: item.1.path] != 0) { key = item.1 }
                    }
                }
            }
            LumiSliderRow(title: LocalizedStringKey(keys(tab).first { $0.1 == key }?.0 ?? "Amount"), value: Binding(get: { model.draft.body.params[keyPath: key.path] }, set: { model.draft.body.params[keyPath: key.path] = $0 }), range: -1...1, onEnd: { model.commit() })
            LumiToggleRow(title: "Background protection", subtitle: "Walls and lines stay straight", isOn: Binding(get: { model.draft.body.protectBackground }, set: { v in model.edit { var b = $0.body; b.protectBackground = v; $0.body = b } }))
        }
    }
}

// MARK: Makeup

struct LooksPanel: View {
    @Bindable var model: EditorModel
    @State private var lookID: String?
    @State private var amount = 0.75
    @State private var reference: PhotosPickerItem?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    LumiToolCircle(symbol: "xmark", value: nil, title: "Off", selected: lookID == nil) { lookID = nil; model.edit { var f = $0.face; f.makeup = MakeupParams(); f.eyes = EyeMakeup(); $0.face = f } }
                    ForEach(MakeupLooks.all) { l in LumiToolCircle(symbol: "face.smiling", value: nil, title: LocalizedStringKey(l.name), selected: lookID == l.id) { lookID = l.id; apply() } }
                }
            }
            LumiSliderRow(title: "Amount", value: $amount, range: 0...1, defaultValue: 0.75, onEnd: { apply() }).disabled(lookID == nil).opacity(lookID == nil ? 0.5 : 1)
            PhotosPicker(selection: $reference, matching: .images) {
                HStack {
                    Image(systemName: "photo.on.rectangle").foregroundStyle(LumiColor.accentText)
                    VStack(alignment: .leading, spacing: 1) { Text("Recreate a look").font(LumiFont.chip()); Text("Copy lip, blush and eye colours from a photo").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(LumiColor.textSecondary) }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(LumiColor.textSecondary)
                }
                .foregroundStyle(LumiColor.text).padding(.horizontal, 14).frame(minHeight: 56).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LumiColor.well))
            }
        }
        .onChange(of: reference) { _, new in Task { await recreate(new) } }
        .alert("Couldn't read a face", isPresented: $failed) {}
    }

    private func apply() {
        guard let l = MakeupLooks.all.first(where: { $0.id == lookID }) else { return }
        let s = MakeupLooks.scaled(l, strength: amount)
        model.edit { var f = $0.face; f.makeup = s.makeup; f.eyes = s.eyes; $0.face = f }
    }

    private func recreate(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let img = CIImage(data: data, options: [.applyOrientationProperty: true]),
              let face = (try? VisionFaceLandmarker().faces(in: img))?.first else { failed = true; return }
        let look = RecreateLook.look(from: RecreateLook.sample(img, face: face))
        model.edit { var f = $0.face; f.makeup = look.makeup; f.eyes = look.eyes; $0.face = f }
    }
}

struct LipsPanel: View {
    enum Part: String, CaseIterable { case lips = "Lips", blush = "Blush", contour = "Contour", highlight = "Highlight", foundation = "Foundation" }
    @Bindable var model: EditorModel
    @State private var part = Part.lips

    var body: some View {
        VStack(spacing: 12) {
            LumiCategoryTabs(items: Part.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $part)
            switch part {
            case .lips:
                HStack(spacing: 8) {
                    ForEach([MakeupParams.Finish.matte, .satin, .gloss], id: \.self) { f in LumiChip(title: LocalizedStringKey(f.rawValue.capitalized), selected: model.draft.face.makeup.lipFinish == f) { model.edit { var x = $0.face; x.makeup.lipFinish = f; $0.face = x } } }
                    LumiChip(title: "Blurred edge", selected: model.draft.face.makeup.ombre > 0) { model.edit { var x = $0.face; x.makeup.ombre = x.makeup.ombre > 0 ? 0 : 0.5; $0.face = x } }
                }
                LumiSwatchRow(colors: LumiPalette.lips, selected: model.draft.face.makeup.lipColor) { c in model.edit { var x = $0.face; x.makeup.lipColor = c; if x.makeup.lipOpacity == 0 { x.makeup.lipOpacity = 0.6 }; $0.face = x } }
                slider("Amount", \.makeup.lipOpacity, .lips)
            case .blush:
                HStack(spacing: 8) { ForEach([MakeupParams.BlushStyle.round, .oval, .wide], id: \.self) { s in LumiChip(title: LocalizedStringKey(s.rawValue.capitalized), selected: model.draft.face.makeup.blushStyle == s) { model.edit { var x = $0.face; x.makeup.blushStyle = s; $0.face = x } } } }
                LumiSwatchRow(colors: LumiPalette.blush, selected: model.draft.face.makeup.blushColor) { c in model.edit { var x = $0.face; x.makeup.blushColor = c; if x.makeup.blushOpacity == 0 { x.makeup.blushOpacity = 0.35 }; $0.face = x } }
                slider("Amount", \.makeup.blushOpacity, .blush)
            case .contour: slider("Contour", \.makeup.contour, .contour)
            case .highlight: slider("Highlight", \.makeup.highlight, .highlight)
            case .foundation: slider("Foundation", \.makeup.foundation, .skin)
            }
        }
    }

    private func slider(_ title: String, _ path: WritableKeyPath<FaceRetouch, Double>, _ mark: FaceMark) -> some View {
        LumiSliderRow(title: LocalizedStringKey(title), value: Binding(get: { model.draft.face[keyPath: path] }, set: { model.draft.face[keyPath: path] = $0 }), range: 0...1, onEnd: { model.commit() })
    }
}

struct EyeMakeupPanel: View {
    enum Part: String, CaseIterable { case shadow = "Shadow", liner = "Liner", lashes = "Lashes", brows = "Brows" }
    enum Side: String, CaseIterable { case both = "Both", left = "Left", right = "Right" }
    @Bindable var model: EditorModel
    @State private var part = Part.shadow
    @State private var side = Side.both

    var body: some View {
        VStack(spacing: 12) {
            LumiCategoryTabs(items: Part.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $part)
            if part != .brows { LumiSegmented(items: Side.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $side, height: 38) }
            switch part {
            case .shadow:
                LumiSwatchRow(colors: LumiPalette.shadow, selected: model.draft.face.eyes.left.shadowColor) { c in
                    model.edit { var f = $0.face; apply(&f) { $0.shadowColor = c; if $0.shadow == 0 { $0.shadow = 0.5 } }; $0.face = f }
                }
                eyeSlider("Amount", \.shadow)
            case .liner:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LinerStyle.allCases, id: \.self) { st in
                            LumiChip(title: LocalizedStringKey(Self.title(st)), selected: (side == .right ? model.draft.face.eyes.right.linerStyle : model.draft.face.eyes.left.linerStyle) == st) {
                                model.edit { var f = $0.face; apply(&f) { $0.linerStyle = st; if $0.liner == 0 { $0.liner = 0.6 } }; $0.face = f }
                            }
                        }
                    }
                }
                eyeSlider("Liner", \.liner)
            case .lashes: eyeSlider("Lashes", \.lashes)
            case .brows:
                HStack(spacing: 8) { ForEach(EyeMakeup.BrowShape.allCases, id: \.self) { s in LumiChip(title: LocalizedStringKey(s.rawValue.capitalized), selected: model.draft.face.eyes.browShape == s) { model.edit { var f = $0.face; f.eyes.browShape = s; $0.face = f } } } }
                LumiSwatchRow(colors: LumiPalette.brows, selected: model.draft.face.eyes.browColor) { c in model.edit { var f = $0.face; f.eyes.browColor = c; if f.eyes.browOpacity == 0 { f.eyes.browOpacity = 0.5 }; $0.face = f } }
                LumiSliderRow(title: "Colour", value: Binding(get: { model.draft.face.eyes.browOpacity }, set: { model.draft.face.eyes.browOpacity = $0 }), range: 0...1, onEnd: { model.commit() })
                LumiSliderRow(title: "Height", value: Binding(get: { model.draft.face.eyes.browHeight }, set: { model.draft.face.eyes.browHeight = $0 }), range: -1...1, onEnd: { model.commit() })
            }
        }
    }

    static func title(_ s: LinerStyle) -> String {
        switch s { case .thin: "Thin"; case .wing: "Wing"; case .catEye: "Cat eye"; case .smudged: "Smudged"; case .double: "Double" }
    }

    private func apply(_ f: inout FaceRetouch, _ change: (inout EyeSide) -> Void) {
        switch side { case .both: f.eyes.setBoth(change); case .left: change(&f.eyes.left); case .right: change(&f.eyes.right) }
    }

    private func eyeSlider(_ title: String, _ path: WritableKeyPath<EyeSide, Double>) -> some View {
        let get: () -> Double = { side == .right ? model.draft.face.eyes.right[keyPath: path] : model.draft.face.eyes.left[keyPath: path] }
        return LumiSliderRow(title: LocalizedStringKey(title), value: Binding(get: get, set: { v in apply(&model.draft.face) { $0[keyPath: path] = v } }), range: 0...1, onEnd: { model.commit() })
    }
}

struct NailsPanel: View {
    @Bindable var model: EditorModel
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: model.nailCount > 0 ? "hand.raised.fingers.spread" : "hand.raised.slash").foregroundStyle(LumiColor.accentText)
                Text(model.nailCount > 0 ? "\(model.nailCount) nails found" : "No hand found. Works best with a clear photo of one hand, fingers apart.").font(LumiFont.caption())
                Spacer()
            }
            HStack(spacing: 8) { ForEach(NailPaint.Finish.allCases, id: \.self) { f in LumiChip(title: LocalizedStringKey(f.rawValue.capitalized), selected: model.draft.face.nails.finish == f) { model.edit { var x = $0.face; x.nails.finish = f; if x.nails.opacity == 0 { x.nails.opacity = 0.9 }; $0.face = x } } } }
            LumiSwatchRow(colors: LumiPalette.nails, selected: model.draft.face.nails.color) { c in model.edit { var x = $0.face; x.nails.color = c; if x.nails.opacity == 0 { x.nails.opacity = 0.9 }; $0.face = x } }
            LumiSliderRow(title: "Amount", value: Binding(get: { model.draft.face.nails.opacity }, set: { model.draft.face.nails.opacity = $0 }), range: 0...1, onEnd: { model.commit() })
        }
        .onAppear { model.refreshNailCount() }
    }
}
