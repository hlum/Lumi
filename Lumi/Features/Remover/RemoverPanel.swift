import SwiftUI

struct RemoverPanel: View {
    enum Tab: String, CaseIterable { case auto = "Auto", brush = "Brush", clone = "Clone" }
    @Bindable var editor: EditorModel
    @State private var remover: RemoverModel?
    @State private var tab = Tab.auto
    @State private var isWorking = false
    @State private var failed = false
    @State private var found: (people: Int, objects: Int, text: Int)?
    @State private var grow = 0                    // extra pixels a quick fix grows the painted mask by (fraction of the long side x 1000)
    @State private var quickFix: SpecialtyBrush?

    var body: some View {
        VStack(spacing: 12) {
            LumiSegmented(items: Tab.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $tab, height: 40)
            if let remover {
                switch tab {
                case .auto: auto(remover)
                case .brush: brush(remover)
                case .clone: clone(remover)
                }
                Text("Runs on your iPhone. Nothing is uploaded.").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(LumiColor.textSecondary)
            } else { ProgressView() }
        }
        .task(id: editor.original?.extent) { if let e = editor.original?.extent { remover = RemoverModel(imageSize: e.size); editor.remover = remover; analyze() } }
        .onDisappear { editor.remover = nil; editor.cloneActive = false }
        .onChange(of: tab) { _, t in editor.cloneActive = (t == .clone); if t != .brush { quickFix = nil; grow = 0 } }
        .alert("Couldn't remove that", isPresented: $failed) {}
    }

    // MARK: tabs

    private func auto(_ r: RemoverModel) -> some View {
        VStack(spacing: 10) {
            Text(summary).font(LumiFont.caption()).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    LumiChip(title: "People", symbol: "person.2") { selectPassersBy(r) }
                    LumiChip(title: "Objects", symbol: "cube") { selectObjects(r) }
                    LumiChip(title: "Text", symbol: "textformat") { selectText(r) }
                    LumiChip(title: "Everything", symbol: "sparkles") { selectPassersBy(r, quiet: true); selectObjects(r, quiet: true); selectText(r, quiet: true) }
                }
            }
            removeBar(r)
        }
    }

    private func brush(_ r: RemoverModel) -> some View {
        VStack(spacing: 10) {
            LumiSegmented(items: [(RemoverModel.Mode.brush, "Paint"), (RemoverModel.Mode.box, "Box")], selection: Bindable(r).mode, height: 38)
            LumiSliderRow(title: "Size", value: Bindable(r).brushSize, range: 0.01...0.15, defaultValue: 0.04, onEnd: {}).disabled(r.mode == .box).opacity(r.mode == .box ? 0.5 : 1)
            removeBar(r)
        }
    }

    private func clone(_ r: RemoverModel) -> some View {
        VStack(spacing: 10) {
            Text("Quick fixes").font(LumiFont.caption()).foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SpecialtyBrush.allCases, id: \.self) { b in
                        LumiChip(title: LocalizedStringKey(b.title), selected: quickFix == b) { quickFix = b; grow = Int(b.grow * 1000); tab = .brush; editor.cloneActive = false }
                    }
                    LumiChip(title: "Noise", symbol: "waveform") { editor.edit { var c = $0.clean; c.denoise = c.denoise > 0 ? 0 : 0.6; $0.clean = c } }
                }
            }
            CleanPanel(model: editor)
        }
    }

    private func removeBar(_ r: RemoverModel) -> some View {
        HStack(spacing: 8) {
            LumiChip(title: "Undo", symbol: "arrow.uturn.backward") { r.undoStroke() }.disabled(!r.canUndo)
            Spacer()
            Button { apply(r) } label: {
                Text(isWorking ? "Removing…" : (r.hasSelection ? "Remove selected" : "Remove")).font(LumiFont.chip()).padding(.horizontal, 20).frame(minHeight: 48)
                    .foregroundStyle(LumiColor.onSelectedPill).background(Capsule().fill(LumiColor.selectedPill))
            }.buttonStyle(.plain).disabled(!r.hasSelection || isWorking).opacity(!r.hasSelection || isWorking ? 0.4 : 1)
        }
    }

    // MARK: finding things

    private var summary: String {
        guard let f = found else { return "Looking for people, objects and text…" }
        let parts = [f.people > 0 ? "\(f.people) \(f.people == 1 ? "person" : "people")" : nil, f.objects > 0 ? "\(f.objects) object\(f.objects == 1 ? "" : "s")" : nil, f.text > 0 ? "\(f.text) text line\(f.text == 1 ? "" : "s")" : nil].compactMap { $0 }
        return parts.isEmpty ? "Nothing found automatically. Switch to Brush and paint it." : "Tap what to remove. Found " + parts.joined(separator: ", ") + "."
    }

    private func analyze() {
        guard let o = editor.original else { return }
        let proxy = Renderer.proxy(o, maxDimension: 768)
        let people = (try? Renderer.services.peopleFinder?.people(in: proxy)) ?? []
        let by = AutoRemove.passersBy(people)
        let objects = (try? Renderer.services.objectFinder?.objects(in: proxy, people: people)) ?? []
        let text = (try? Renderer.services.textFinder?.textBoxes(in: proxy)) ?? []
        found = (by.count, objects.count, text.count)
    }

    private func selectPassersBy(_ r: RemoverModel, quiet: Bool = false) {
        guard let o = editor.original, let finder = Renderer.services.peopleFinder,
              let people = try? finder.people(in: Renderer.proxy(o, maxDimension: 1024)) else { if !quiet { failed = true }; return }
        let by = AutoRemove.passersBy(people)
        guard let mask = AutoRemove.combinedMask(by, extent: Renderer.proxy(o, maxDimension: 1024).extent) else { if !quiet { failed = true }; return }
        r.select(mask, extent: Renderer.proxy(o, maxDimension: 1024).extent)
    }

    private func selectObjects(_ r: RemoverModel, quiet: Bool = false) {
        guard let o = editor.original, let finder = Renderer.services.objectFinder else { if !quiet { failed = true }; return }
        let proxy = Renderer.proxy(o, maxDimension: 1024)
        let people = (try? Renderer.services.peopleFinder?.people(in: proxy)) ?? []
        guard let objs = try? finder.objects(in: proxy, people: people), let mask = AutoRemove.combinedMask(objs, extent: proxy.extent) else { if !quiet { failed = true }; return }
        r.select(mask, extent: proxy.extent)
    }

    private func selectText(_ r: RemoverModel, quiet: Bool = false) {
        guard let o = editor.original, let finder = Renderer.services.textFinder else { if !quiet { failed = true }; return }
        let proxy = Renderer.proxy(o, maxDimension: 1024)
        guard let boxes = try? finder.textBoxes(in: proxy), let mask = AutoRemove.textMask(boxes, extent: proxy.extent) else { if !quiet { failed = true }; return }
        r.select(mask, extent: proxy.extent)
    }

    private func apply(_ r: RemoverModel) {
        guard let taken = r.take() else { return }
        let mask = grow > 0 ? taken.dilated(by: max(1, Int(Double(grow) / 1000 * Double(max(taken.width, taken.height))))) : taken
        isWorking = true
        Task.detached {
            await MainActor.run {
                editor.edit { $0.removals = $0.removals + [mask] }
                isWorking = false
                quickFix = nil; grow = 0
            }
        }
    }
}
