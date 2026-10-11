import PhotosUI
import SwiftUI

struct EditorView: View {
    @State private var model = EditorModel()
    @State private var item: PhotosPickerItem?
    @State private var loadFailed = false

    var body: some View {
        VStack {
            if model.preview != nil {
                MetalPreviewView(image: model.preview)
                    .onLongPressGesture(minimumDuration: 0.1, pressing: { model.showOriginal = $0 }, perform: {})
                Slider(value: $model.draftExposure, in: -2...2) { editing in
                    if !editing { model.commitExposure() }
                }
                .padding(.horizontal)
            } else {
                ContentUnavailableView("Pick a photo", systemImage: "photo")
            }
        }
        .navigationTitle("Editor")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { PhotosPicker("Photo", selection: $item, matching: .images) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.canRedo)
                Button("Save", systemImage: "square.and.arrow.down") { Task { await model.save() } }.disabled(model.original == nil)
            }
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                if let data = try? await new.loadTransferable(type: Data.self), (try? model.load(data: data)) != nil { loadFailed = false }
                else { loadFailed = true }
            }
        }
        .alert("Couldn't open that photo", isPresented: $loadFailed) {}
        .alert("Couldn't save", isPresented: .constant(model.saveError != nil)) {}
    }
}
