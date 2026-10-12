import CoreImage
import SwiftUI

/// Paints into a mask held somewhere in the document (the eraser of a light or filter).
struct MaskPaintOverlay: View {
    @Bindable var model: EditorModel
    let imageSize: CGSize
    var committed: () -> MaskCanvas?
    var write: (MaskCanvas?) -> Void
    var brushSize = 0.06
    @State private var remover: RemoverModel?

    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = map.toImageClamped(v.location)
                    if remover == nil { remover = RemoverModel(imageSize: imageSize); remover?.brushSize = brushSize; remover?.begin(at: p) } else { remover?.move(to: p) }
                    guard let r = remover else { return }
                    if var base = committed(), base.width == r.mask.width, base.height == r.mask.height { base.union(r.mask); write(base) } else { write(r.mask) }
                }
                .onEnded { _ in remover = nil; model.commit() })
        }
    }
}

// MARK: AI Flash

struct RelightPanel: View {
    @Bindable var model: EditorModel
    static let symbols: [RelightStyle: String] = [.flash: "bolt.fill", .fillLight: "sun.max", .night: "moon.stars", .backlit: "person.crop.square", .photoBooth: "camera.metering.center.weighted", .ledStrip: "light.strip.2", .redLight: "lightbulb.fill", .goldenHour: "sun.horizon"]
    var styles = RelightStyle.aiFlash

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach(styles, id: \.self) { s in
                    Button { model.edit { var r = $0.relight; r.style = s; if r.strength == 0 { r.strength = 0.55 }; $0.relight = r } } label: {
                        VStack(spacing: 6) {
                            Image(systemName: Self.symbols[s] ?? "sparkles").font(.system(size: 22)).frame(maxWidth: .infinity, minHeight: 60)
                                .foregroundStyle(active(s) ? LumiColor.onAccent : LumiColor.text)
                                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(active(s) ? LumiColor.accent : LumiColor.well))
                            Text(LocalizedStringKey(s.title)).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(LumiColor.text).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }.buttonStyle(.plain).accessibilityAddTraits(active(s) ? .isSelected : [])
                }
            }
            HStack(spacing: 8) {
                LumiSliderRow(title: "Strength", value: Binding(get: { model.draft.relight.strength }, set: { model.draft.relight.strength = $0 }), range: 0...1, defaultValue: 0.55, onEnd: { model.commit() })
                Button { model.lightEraserActive.toggle() } label: {
                    Image(systemName: "eraser").frame(width: 48, height: 48).foregroundStyle(model.lightEraserActive ? LumiColor.onAccent : LumiColor.text)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(model.lightEraserActive ? LumiColor.accent : LumiColor.well))
                }.buttonStyle(.plain).accessibilityLabel("Erase light from parts of the photo")
            }
            HStack {
                Text(model.lightEraserActive ? "Paint where the light should go away" : "Light falls on the person; the rest stays as shot.").font(.footnote).foregroundStyle(LumiColor.textSecondary)
                Spacer()
                if model.draft.relight.erase != nil { LumiChip(title: "Clear erase") { model.edit { var r = $0.relight; r.erase = nil; $0.relight = r } } }
                if model.draft.relight.strength > 0 { LumiChip(title: "Off") { model.edit { $0.relight = RelightConfig() } } }
            }
        }
        .onDisappear { model.lightEraserActive = false }
    }

    private func active(_ s: RelightStyle) -> Bool { model.draft.relight.style == s && model.draft.relight.strength > 0 }
}

// MARK: Effects

struct EffectsPanel: View {
    enum Tab: String, CaseIterable { case light = "Light", classic = "Classic", move = "Move" }
    @Bindable var model: EditorModel
    @State private var tab = Tab.light

    var body: some View {
        VStack(spacing: 12) {
            LumiSegmented(items: Tab.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $tab, height: 40)
            switch tab {
            case .light: RelightPanel(model: model, styles: RelightStyle.coloured)
            case .classic:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        LumiChip(title: "None", selected: model.draft.effect.strength == 0) { model.edit { $0.effect = PhotoEffectConfig() } }
                        ForEach(PhotoEffect.allCases, id: \.self) { e in
                            LumiChip(title: LocalizedStringKey(Self.name(e)), selected: model.draft.effect.effect == e && model.draft.effect.strength > 0) { model.edit { var c = $0.effect; c.effect = e; if c.strength == 0 { c.strength = 0.6 }; $0.effect = c } }
                        }
                    }
                }
                LumiSliderRow(title: "Strength", value: Binding(get: { model.draft.effect.strength }, set: { model.draft.effect.strength = $0 }), range: 0...1, defaultValue: 0.6, onEnd: { model.commit() })
                    .disabled(model.draft.effect.strength == 0).opacity(model.draft.effect.strength == 0 ? 0.5 : 1)
            case .move: MovePanel(model: model)
            }
        }
        .onChange(of: tab) { _, t in if t != .move { model.stopMotion() } }
        .onDisappear { model.stopMotion() }
    }

    static func name(_ e: PhotoEffect) -> String {
        switch e { case .glitch: "Glitch"; case .lightLeak: "Light leak"; case .particles: "Particles"; case .zoomBlur: "Zoom blur"; case .softGlow: "Soft glow" }
    }
}

struct MovePanel: View {
    @Bindable var model: EditorModel
    @State private var style = AnimatePhoto.Style.zoomIn
    @State private var intensity = 0.5
    @State private var duration = 3.0
    @State private var saved = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AnimatePhoto.Style.allCases, id: \.self) { s in
                        LumiChip(title: LocalizedStringKey(Self.title(s)), selected: model.motion?.style == s) { style = s; start() }
                    }
                }
            }
            LumiSliderRow(title: "Amount", value: $intensity, range: 0...1, defaultValue: 0.5, onEnd: { if model.motion != nil { start() } })
            HStack(spacing: 8) {
                LumiChip(title: model.motion == nil ? "Preview" : "Stop", symbol: model.motion == nil ? "play.fill" : "stop.fill") { if model.motion == nil { start() } else { model.stopMotion() } }
                LumiChip(title: "Save as GIF", symbol: "square.and.arrow.down") { Task { saved = await model.saveMotionGIF() } }.disabled(model.motion == nil)
            }
            if saved { Text("Saved to Photos").font(.footnote).foregroundStyle(LumiColor.textSecondary) }
        }
    }

    private func start() { model.startMotion(AnimatePhoto(style: style, duration: duration, fps: 24, intensity: intensity)); saved = false }
    static func title(_ s: AnimatePhoto.Style) -> String {
        switch s { case .zoomIn: "Zoom in"; case .zoomOut: "Zoom out"; case .panLeft: "Pan left"; case .panRight: "Pan right"; case .parallax: "Parallax" }
    }
}
