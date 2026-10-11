import PhotosUI
import SwiftUI

struct RecipesView: View {
    @State private var library = RecipeLibrary()
    @State private var query = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var batch = BatchModel()
    @State private var chosen: Recipe?
    @State private var photos: [(name: String, data: Data)] = []
    @State private var cutoutItems: [PhotosPickerItem] = []
    @State private var cutoutBackground = CutoutConfig.Background.transparent

    var body: some View {
        list
            .searchable(text: $query)
            .navigationTitle("Recipes")
            .toolbar { toolbar }
            .onChange(of: items) { _, new in Task { await load(new) } }
            .onChange(of: cutoutItems) { _, new in Task { await runCutout(new) } }
            .confirmationDialog("Apply to \(photos.count) photos", isPresented: Binding(get: { chosen != nil && !photos.isEmpty }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible) {
                Button("Apply and save") { applyChosen() }
            }
    }

    private var list: some View {
        List {
            Section("Starter looks") { ForEach(library.starters.filter(matches)) { row($0) } }
            Section("My recipes") { mine }
            if batch.isRunning || !batch.items.isEmpty { Section("Batch") { progress } }
        }
    }

    @ViewBuilder private var mine: some View {
        if library.mine.isEmpty { Text("Save a look from the editor and it appears here.").font(.caption).foregroundStyle(.secondary) }
        ForEach(library.mine.filter(matches)) { r in
            row(r).swipeActions {
                Button("Delete", role: .destructive) { library.delete(r.id) }
                Button(r.isFavorite ? "Unfavorite" : "Favorite") { library.toggleFavorite(r.id) }.tint(.yellow)
            }
        }
    }

    @ViewBuilder private var progress: some View {
        ProgressView(value: batch.progress)
        ForEach(batch.items) { i in
            HStack { Text(i.name); Spacer(); status(i.status) }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { PhotosPicker("Batch", selection: $items, matching: .images) }
        ToolbarItem(placement: .topBarTrailing) { cutoutMenu }
        ToolbarItem(placement: .topBarLeading) { if batch.isRunning { Button("Cancel", role: .cancel) { batch.cancel() } } }
    }

    private var cutoutMenu: some View {
        Menu("Batch cutout", systemImage: "person.crop.rectangle") {
            Picker("Background", selection: $cutoutBackground) {
                Text("Transparent").tag(CutoutConfig.Background.transparent)
                Text("White").tag(CutoutConfig.Background.color(.white))
                Text("Black").tag(CutoutConfig.Background.color(.black))
            }
            PhotosPicker("Choose up to 30 photos", selection: $cutoutItems, maxSelectionCount: BatchModel.maxCutoutPhotos, matching: .images)
        }
    }

    private func matches(_ r: Recipe) -> Bool { query.isEmpty || r.name.localizedCaseInsensitiveContains(query) }

    private func row(_ r: Recipe) -> some View {
        Button { chosen = r } label: {
            HStack {
                Text(r.name); Spacer()
                if r.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                Text("\(r.operations.count)").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func status(_ s: BatchModel.Item.Status) -> some View {
        switch s {
        case .waiting: Image(systemName: "clock")
        case .working: ProgressView()
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
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
