import PhotosUI
import SwiftUI

struct RecipesView: View {
    @State private var library = RecipeLibrary()
    @State private var query = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var batch = BatchModel()
    @State private var chosen: Recipe?
    @State private var photos: [(name: String, data: Data)] = []

    var body: some View {
        List {
            Section("Starter looks") { ForEach(library.starters.filter(matches)) { row($0) } }
            Section("My recipes") {
                if library.mine.isEmpty { Text("Save a look from the editor and it appears here.").font(.caption).foregroundStyle(.secondary) }
                ForEach(library.mine.filter(matches)) { r in
                    row(r).swipeActions {
                        Button("Delete", role: .destructive) { library.delete(r.id) }
                        Button(r.isFavorite ? "Unfavorite" : "Favorite") { library.toggleFavorite(r.id) }.tint(.yellow)
                    }
                }
            }
            if batch.isRunning || !batch.items.isEmpty {
                Section("Batch") {
                    ProgressView(value: batch.progress)
                    ForEach(batch.items) { i in
                        HStack { Text(i.name); Spacer(); status(i.status) }
                    }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Recipes")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { PhotosPicker("Batch", selection: $items, matching: .images) } }
        .onChange(of: items) { _, new in Task { await load(new) } }
        .confirmationDialog("Apply to \(photos.count) photos", isPresented: Binding(get: { chosen != nil && !photos.isEmpty }, set: { if !$0 { chosen = nil } }), titleVisibility: .visible) {
            Button("Apply and save") { if let r = chosen { library.markUsed(r.id); Task { await batch.run(photos, recipe: r) } } }
        }
    }

    private func matches(_ r: Recipe) -> Bool { query.isEmpty || r.name.localizedCaseInsensitiveContains(query) }

    private func row(_ r: Recipe) -> some View {
        Button { chosen = r } label: {
            HStack { Text(r.name); Spacer(); if r.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }; Text("\(r.operations.count)").foregroundStyle(.secondary) }
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

    private func load(_ new: [PhotosPickerItem]) async {
        var out: [(String, Data)] = []
        for (i, item) in new.enumerated() { if let d = try? await item.loadTransferable(type: Data.self) { out.append(("Photo \(i + 1)", d)) } }
        photos = out
    }
}
