import PhotosUI
import SwiftUI

/// Cuts the subject out of up to 30 photos and saves each one.
struct BatchCutoutView: View {
    @State private var items: [PhotosPickerItem] = []
    @State private var batch = BatchModel()
    @State private var background = CutoutConfig.Background.transparent
    @State private var photos: [(name: String, data: Data)] = []
    private static let backgrounds: [(String, CutoutConfig.Background)] = [("Clear", .transparent), ("White", .color(.white)), ("Black", .color(.black)), ("Sky", .gradient(RGBA(r: 0.55, g: 0.75, b: 1, a: 1), .white))]

    var body: some View {
        ToolScaffold(title: "Batch cutout") {
            ScrollView {
                VStack(spacing: 8) {
                    if batch.items.isEmpty { Text("Choose up to \(BatchModel.maxCutoutPhotos) photos. Each one is cut out and saved.").font(LumiFont.body()).foregroundStyle(LumiColor.textSecondary).padding(.top, 40) }
                    ForEach(batch.items) { i in
                        HStack { Text(i.name).font(LumiFont.body()); Spacer(); status(i.status) }
                            .padding(.horizontal, 14).frame(minHeight: 52).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LumiColor.surface))
                    }
                }
            }
        } panel: {
            if batch.isRunning || !batch.items.isEmpty { ProgressView(value: batch.progress).tint(LumiColor.accent); Text("\(batch.completed) of \(batch.items.count) done").font(LumiFont.caption()) }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(Self.backgrounds, id: \.0) { b in LumiChip(title: LocalizedStringKey(b.0), selected: background == b.1) { background = b.1 } } } }
            if batch.isRunning { LumiPrimaryButton(title: "Cancel", symbol: "xmark") { batch.cancel() } }
            else {
                PhotosPicker(selection: $items, maxSelectionCount: BatchModel.maxCutoutPhotos, matching: .images) {
                    Label(batch.items.isEmpty ? "Choose photos" : "Choose more", systemImage: "photo.on.rectangle").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(LumiColor.onAccent).background(Capsule().fill(LumiColor.accent))
                }
            }
        }
        .onChange(of: items) { _, new in Task { await run(new) } }
    }

    @ViewBuilder private func status(_ s: BatchModel.Item.Status) -> some View {
        switch s {
        case .waiting: Image(systemName: "clock").foregroundStyle(LumiColor.textSecondary)
        case .working: ProgressView()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LumiColor.destructive)
        }
    }

    private func run(_ new: [PhotosPickerItem]) async {
        var out: [(String, Data)] = []
        for (i, it) in new.enumerated() { if let d = try? await it.loadTransferable(type: Data.self) { out.append(("Photo \(i + 1)", d)) } }
        photos = out
        await batch.runCutout(out, background: background, masker: Renderer.services.subjectMasker)
    }
}
