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
        case .shade: [FaceSlider(title: "3D shading", path: \.ratio.shade3D, range: 0...1, mark: .contour)]
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
