import SwiftUI

struct RemoverPanel: View {
    @Bindable var editor: EditorModel
    @State private var remover: RemoverModel?
    @State private var isWorking = false
    @State private var failed = false

    var body: some View {
        VStack {
            if let remover {
                Picker("Mode", selection: Bindable(remover).mode) { Text("Brush").tag(RemoverModel.Mode.brush); Text("Box").tag(RemoverModel.Mode.box) }
                    .pickerStyle(.segmented).padding(.horizontal)
                Slider(value: Bindable(remover).brushSize, in: 0.01...0.15).padding(.horizontal).disabled(remover.mode == .box)
                HStack {
                    Button("People", systemImage: "person.2") { selectPassersBy(remover) }.buttonStyle(LumiButtonStyle())
                    Button("Text", systemImage: "textformat") { selectText(remover) }.buttonStyle(LumiButtonStyle())
                    Button("Undo stroke", systemImage: "arrow.uturn.backward") { remover.undoStroke() }.disabled(!remover.canUndo)
                    Button(isWorking ? "Removing…" : "Remove") { apply(remover) }.buttonStyle(LumiButtonStyle(prominent: true)).disabled(!remover.hasSelection || isWorking)
                }.labelStyle(.iconOnly)
            } else { ProgressView() }
        }
        .task(id: editor.original?.extent) { if let e = editor.original?.extent { remover = RemoverModel(imageSize: e.size); editor.remover = remover } }
        .onDisappear { editor.remover = nil }
        .alert("Couldn't remove that", isPresented: $failed) {}
    }

    private func selectPassersBy(_ r: RemoverModel) {
        guard let o = editor.original, let finder = Renderer.services.peopleFinder,
              let people = try? finder.people(in: Renderer.proxy(o, maxDimension: 1024)) else { failed = true; return }
        let by = AutoRemove.passersBy(people)
        guard let mask = AutoRemove.combinedMask(by, extent: Renderer.proxy(o, maxDimension: 1024).extent) else { failed = true; return }
        r.select(mask, extent: Renderer.proxy(o, maxDimension: 1024).extent)
    }

    private func selectText(_ r: RemoverModel) {
        guard let o = editor.original, let finder = Renderer.services.textFinder else { failed = true; return }
        let proxy = Renderer.proxy(o, maxDimension: 1024)
        guard let boxes = try? finder.textBoxes(in: proxy), let mask = AutoRemove.textMask(boxes, extent: proxy.extent) else { failed = true; return }
        r.select(mask, extent: proxy.extent)
    }

    private func apply(_ r: RemoverModel) {
        guard let mask = r.take() else { return }
        isWorking = true
        Task.detached {
            await MainActor.run {
                editor.edit { $0.removals = $0.removals + [mask] }
                isWorking = false
            }
        }
    }
}
