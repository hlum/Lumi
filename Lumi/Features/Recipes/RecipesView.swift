import PhotosUI
import SwiftUI

struct RecipesView: View {
    enum Tab: String, CaseIterable { case mine = "Mine", starters = "Starters", favorites = "Favorites" }
    @State private var library = RecipeLibrary()
    @State private var tab = Tab.starters
    @State private var query = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var batch = BatchModel()
    @State private var chosen: Recipe?
    @State private var photos: [(name: String, data: Data)] = []
    @State private var cutoutItems: [PhotosPickerItem] = []
    @State private var cutoutBackground = CutoutConfig.Background.transparent
    @State private var importing = false

    private var shown: [Recipe] {
        let base: [Recipe]
        switch tab { case .mine: base = library.mine; case .starters: base = library.starters; case .favorites: base = library.mine.filter(\.isFavorite) }
        return base.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search recipes", text: $query).lumiField()
                LumiSegmented(items: Tab.allCases.map { ($0, LocalizedStringKey($0.rawValue)) }, selection: $tab, height: 44)
                ForEach(shown) { r in card(r) }
                if shown.isEmpty { Text(tab == .starters ? "No match." : "Save a look from the editor and it appears here.").font(LumiFont.body()).foregroundStyle(LumiColor.textSecondary).padding(.vertical, 20) }
                if batch.isRunning || !batch.items.isEmpty { progress }
                HStack(spacing: 10) {
                    PhotosPicker(selection: $items, matching: .images) { wide("Apply a recipe to many photos", "photo.stack") }.buttonStyle(.plain)
                }
                Menu {
                    Picker("Background", selection: $cutoutBackground) {
                        Text("Transparent").tag(CutoutConfig.Background.transparent); Text("White").tag(CutoutConfig.Background.color(.white)); Text("Black").tag(CutoutConfig.Background.color(.black))
                    }
                    PhotosPicker("Choose up to \(BatchModel.maxCutoutPhotos) photos", selection: $cutoutItems, maxSelectionCount: BatchModel.maxCutoutPhotos, matching: .images)
                } label: { wide("Batch cutout", "person.crop.rectangle") }
            }
            .padding(.horizontal, LumiShape.margin).padding(.bottom, 24)
        }
        .background(LumiColor.ground.ignoresSafeArea())
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Import") { importing = true }.font(LumiFont.chip()) }
            ToolbarItem(placement: .topBarLeading) { if batch.isRunning { Button("Cancel", role: .cancel) { batch.cancel() } } }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { r in
            if case .success(let u) = r, u.startAccessingSecurityScopedResource() { defer { u.stopAccessingSecurityScopedResource() }; if let d = try? Data(contentsOf: u) { _ = try? library.importFile(d); tab = .mine } }
        }
        .onChange(of: items) { _, new in Task { await load(new); if !photos.isEmpty, chosen == nil { chosen = shown.first } } }
        .onChange(of: cutoutItems) { _, new in Task { await runCutout(new) } }
        .confirmationDialog("Apply to \(photos.count) photos", isPresented: Binding(get: { chosen != nil && !photos.isEmpty }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible) {
            Button("Apply and save") { applyChosen() }
        } message: { Text(chosen?.name ?? "") }
    }

    private func card(_ r: Recipe) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(LumiFont.headline()).foregroundStyle(LumiColor.text)
                Text(r.summary).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(LumiColor.textSecondary)
                if r.useCount > 0 { Text("Used \(r.useCount) time\(r.useCount == 1 ? "" : "s")").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(LumiColor.textSecondary) }
            }
            Spacer()
            if tab != .starters {
                Button { library.toggleFavorite(r.id) } label: { Image(systemName: r.isFavorite ? "star.fill" : "star").foregroundStyle(r.isFavorite ? LumiColor.accent : LumiColor.textSecondary).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(r.isFavorite ? "Remove from favourites" : "Add to favourites")
            }
            Button { chosen = r; if photos.isEmpty { items = [] } } label: {
                Text("Apply").font(LumiFont.chip()).padding(.horizontal, 16).frame(minHeight: 40).foregroundStyle(LumiColor.onSelectedPill).background(Capsule().fill(LumiColor.selectedPill))
            }.buttonStyle(.plain)
        }
        .padding(14).background(RoundedRectangle(cornerRadius: LumiShape.tile, style: .continuous).fill(LumiColor.surface))
        .contextMenu { if tab != .starters { Button("Delete", systemImage: "trash", role: .destructive) { library.delete(r.id) } } }
    }

    private func wide(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        HStack { Image(systemName: symbol).foregroundStyle(LumiColor.accentText); Text(title).font(LumiFont.headline()); Spacer(); Image(systemName: "chevron.right").foregroundStyle(LumiColor.textSecondary) }
            .foregroundStyle(LumiColor.text).padding(.horizontal, 16).frame(minHeight: 60).background(RoundedRectangle(cornerRadius: LumiShape.tile, style: .continuous).fill(LumiColor.surface))
    }

    @ViewBuilder private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: batch.progress).tint(LumiColor.accent)
            ForEach(batch.items) { i in HStack { Text(i.name).font(LumiFont.body()); Spacer(); status(i.status) } }
        }.padding(14).background(RoundedRectangle(cornerRadius: LumiShape.tile, style: .continuous).fill(LumiColor.surface))
    }

    @ViewBuilder private func status(_ s: BatchModel.Item.Status) -> some View {
        switch s {
        case .waiting: Image(systemName: "clock").foregroundStyle(LumiColor.textSecondary)
        case .working: ProgressView()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(LumiColor.destructive)
        }
    }

    private func applyChosen() {
        guard let r = chosen else { return }
        library.markUsed(r.id)
        Task { await batch.run(photos, recipe: r) }
    }

    private func runCutout(_ new: [PhotosPickerItem]) async {
        await load(new)
        await batch.runCutout(photos, background: cutoutBackground, masker: Renderer.services.subjectMasker)
    }

    private func load(_ new: [PhotosPickerItem]) async {
        var out: [(String, Data)] = []
        for (i, item) in new.enumerated() { if let d = try? await item.loadTransferable(type: Data.self) { out.append(("Photo \(i + 1)", d)) } }
        photos = out
    }
}
