import PhotosUI
import SwiftUI

struct IDPhotoView: View {
    @State private var model = IDPhotoModel()
    @State private var item: PhotosPickerItem?
    @State private var message: LocalizedStringKey?
    static let backgrounds: [(name: String, color: RGBA)] = [
        ("White", RGBA(r: 1, g: 1, b: 1, a: 1)), ("Blue", RGBA(r: 0.2, g: 0.45, b: 0.85, a: 1)), ("Red", RGBA(r: 0.85, g: 0.15, b: 0.15, a: 1)), ("Gray", RGBA(r: 0.92, g: 0.92, b: 0.92, a: 1)),
    ]

    var body: some View {
        ToolScaffold(title: "ID photo", trailing: AnyView(PhotosPicker(selection: $item, matching: .images) { Image(systemName: "photo.badge.plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(LumiColor.text).frame(width: 44, height: 44).background(Circle().fill(LumiColor.surface)) }.accessibilityLabel("Choose photo"))) {
            ZStack {
                CIImageFrame(image: model.result, placeholder: "Choose a front-facing photo")
                if model.result != nil, let c = model.check { GuideOverlay(spec: model.spec, passes: c.passes) }
            }
        } panel: {
            if model.source == nil {
                PhotosPicker(selection: $item, matching: .images) { Label("Choose a photo", systemImage: "photo").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.onAccent).background(Capsule().fill(LumiColor.accent)) }
            } else if model.noFace {
                Text("No face found. Use a photo of one person facing the camera.").font(LumiFont.body()).multilineTextAlignment(.center)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(model.specs) { s in LumiChip(title: LocalizedStringKey(s.name), selected: model.spec == s) { model.choose(s) } } }
                }
                LumiSwatchRow(colors: Self.backgrounds, selected: model.background) { model.setBackground($0) }
                if let c = model.check {
                    HStack(spacing: 14) { tick("Head size", c.headSizeOK); tick("Centered", c.centeredOK); tick("Not tilted", c.levelOK); tick("Eye line", c.eyeLineOK) }
                }
                HStack(spacing: 10) {
                    LumiPrimaryButton(title: "Save photo", symbol: "square.and.arrow.down") { Task { message = await model.save() ? "Saved to Photos" : "Couldn't save" } }
                    LumiPrimaryButton(title: "Print sheet", symbol: "printer") { Task { message = await model.save(sheet: CGSize(width: 102, height: 152)) ? "Sheet saved to Photos" : "Couldn't save" } }
                }
                if let message { Text(message).font(.footnote).foregroundStyle(LumiColor.textSecondary) }
            }
        }
        .onChange(of: item) { _, new in Task { if let d = try? await new?.loadTransferable(type: Data.self) { model.load(d) } } }
    }

    private func tick(_ title: LocalizedStringKey, _ ok: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").font(.system(size: 20)).foregroundStyle(ok ? Color.green : LumiColor.destructive)
            Text(title).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(LumiColor.text)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityValue(ok ? "OK" : "Needs attention")
    }
}

/// Head oval and eye line drawn on the finished photo; green when every check passes.
private struct GuideOverlay: View {
    var spec: IDSpec?
    var passes: Bool
    var body: some View {
        GeometryReader { geo in
            if let spec {
                let aspect = spec.aspect
                let h = min(geo.size.height, geo.size.width / aspect), w = h * aspect
                let x = (geo.size.width - w) / 2, y = (geo.size.height - h) / 2
                let head = (spec.headMin + spec.headMax) / 2 * h
                Path { p in
                    p.addEllipse(in: CGRect(x: x + w / 2 - head * 0.38, y: y + spec.eyeLine * h - head * 0.45, width: head * 0.76, height: head))
                    p.move(to: CGPoint(x: x, y: y + spec.eyeLine * h)); p.addLine(to: CGPoint(x: x + w, y: y + spec.eyeLine * h))
                }.stroke(passes ? Color.green : .white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).opacity(0.85)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
