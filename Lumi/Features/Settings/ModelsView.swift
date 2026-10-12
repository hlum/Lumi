import SwiftUI
import UniformTypeIdentifiers

/// Settings > AI models: see which model does each job, switch between installed ones, or bring a better one.
struct ModelsView: View {
    private let store = ModelStore.shared
    @State private var revision = 0
    @State private var importing = false
    @State private var picked: PickedModel?
    @State private var error: String?

    struct PickedModel: Identifiable { let id = UUID(); var url: URL; var inputs: [String]; var outputs: [String] }

    var body: some View {
        List {
            Section { Text("Each tool runs a model on your iPhone. You can install a better one for a job; it needs inputs and outputs named the way the job expects.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(ModelSlot.allCases) { slot in
                let entries = store.entries(slot), active = store.active(slot)
                Section(slot.title) {
                    if entries.isEmpty { Text("No model installed").foregroundStyle(.secondary) }
                    ForEach(entries) { e in
                        Button { try? store.select(e.id, for: slot); revision += 1 } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.title).font(.headline)
                                    Text([e.version.isEmpty ? nil : "v\(e.version)", e.license.isEmpty ? nil : e.license, e.bundled ? "Built in" : "Installed"].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if e.id == active?.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(LumiColor.accent) }
                            }
                        }
                        .swipeActions { if !e.bundled { Button("Remove", role: .destructive) { try? store.remove(e.id); revision += 1 } } }
                    }
                    if let a = active, !a.bundled, store.entries(slot).contains(where: \.bundled) { Button("Use the built-in model") { store.reset(slot); revision += 1 } }
                }
            }
            Section { Button("Install a model…", systemImage: "square.and.arrow.down") { importing = true } }
        }
        .id(revision)
        .navigationTitle("AI models")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item, .folder]) { result in
            guard case .success(let url) = result else { return }
            Task { await inspect(url) }
        }
        .sheet(item: $picked) { p in ModelImportForm(picked: p, store: store) { revision += 1; picked = nil } }
        .alert("Couldn't read that model", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { } message: { Text(error ?? "") }
    }

    private func inspect(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // copy first: the sheet outlives the access grant
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let local = tmp.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: local)
            let io = try await store.inspect(local)
            picked = PickedModel(url: local, inputs: io.inputs, outputs: io.outputs)
        } catch { self.error = "Use a Core ML model (.mlpackage, .mlmodel or .mlmodelc)." }
    }
}

struct ModelImportForm: View {
    let picked: ModelsView.PickedModel
    let store: ModelStore
    var done: () -> Void
    @State private var slot = ModelSlot.inpaint
    @State private var title = ""
    @State private var version = "1"
    @State private var license = ""
    @State private var author = ""
    @State private var mapping: [String: String] = [:]
    @State private var side = ""
    @State private var scale = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Job") {
                    Picker("This model does", selection: $slot) { ForEach(ModelSlot.allCases) { Text($0.title).tag($0) } }
                    Text(slot.hint).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Details") {
                    TextField("Name", text: $title); TextField("Version", text: $version); TextField("Author", text: $author); TextField("Licence (you are responsible for it)", text: $license)
                }
                Section("Match the model's features") {
                    ForEach(slot.inputRoles, id: \.self) { role in feature(role, picked.inputs) }
                    ForEach(slot.outputRoles, id: \.self) { role in feature(role, picked.outputs) }
                }
                Section("Sizes") {
                    TextField("Side (pixels)", text: $side).keyboardType(.numberPad)
                    if slot == .upscale { TextField("Scale", text: $scale).keyboardType(.numberPad) }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Install model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done() } }
                ToolbarItem(placement: .confirmationAction) { Button(working ? "Installing…" : "Install") { Task { await install() } }.disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear { title = (picked.url.deletingPathExtension().lastPathComponent); autoMap() }
            .onChange(of: slot) { _, _ in autoMap() }
        }
    }

    private func feature(_ role: String, _ names: [String]) -> some View {
        Picker(role.capitalized, selection: Binding(get: { mapping[role] ?? "" }, set: { mapping[role] = $0 })) {
            Text("Choose").tag("")
            ForEach(names, id: \.self) { Text($0).tag($0) }
        }
    }

    /// If the model has exactly one feature that fits, or a feature named like the role, pick it.
    private func autoMap() {
        mapping = [:]
        for r in slot.inputRoles { mapping[r] = picked.inputs.contains(r) ? r : (slot.inputRoles.count == 1 && picked.inputs.count == 1 ? picked.inputs[0] : "") }
        for r in slot.outputRoles { mapping[r] = picked.outputs.contains(r) ? r : (picked.outputs.count == 1 ? picked.outputs[0] : "") }
    }

    private func install() async {
        working = true; defer { working = false }
        let io = mapping.filter { !$0.value.isEmpty }
        let slug = title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        var e = ModelEntry(id: slug.isEmpty ? UUID().uuidString : slug, slot: slot, title: title, version: version.isEmpty ? "1" : version, author: author, license: license, file: "", io: io)
        e.side = Int(side); e.scale = Int(scale)
        do { try await store.install(from: picked.url, as: e); done() }
        catch ModelStoreError.incompatible(let miss) { error = "The model doesn't have: \(miss.joined(separator: ", "))." }
        catch ModelStoreError.unmappedRoles(let r) { error = "Choose a feature for: \(r.joined(separator: ", "))." }
        catch { self.error = "Couldn't install that model." }
    }
}
