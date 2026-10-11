import PhotosUI
import SwiftUI

struct CollageView: View {
    @State private var items: [PhotosPickerItem] = []
    @State private var photos: [CIImage] = []
    @State private var state: CollageState?
    @State private var shown: CGImage?
    @State private var saved = false
    private let saver = LibraryPhotoSaver()

    var body: some View {
        VStack {
            if let shown {
                Image(decorative: shown, scale: 1).resizable().scaledToFit().padding()
                if let s = state {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(CollageLayout.builtin.filter { $0.slots.count == photos.count }.prefix(24)) { l in
                                Button(l.name) { state = CollageState(layout: l, photoCount: photos.count); redraw() }.buttonStyle(.bordered)
                                    .tint(l.id == s.layout.id ? .accentColor : .secondary)
                            }
                        }.padding(.horizontal)
                    }
                    HStack {
                        Text("Border").font(.caption)
                        Slider(value: Binding(get: { s.border }, set: { state?.border = $0; redraw() }), in: 0...0.05)
                    }.padding(.horizontal)
                    HStack {
                        Text("Corners").font(.caption)
                        Slider(value: Binding(get: { s.cornerRadius }, set: { state?.cornerRadius = $0; redraw() }), in: 0...0.5)
                    }.padding(.horizontal)
                }
            } else {
                ContentUnavailableView("Pick 2–9 photos", systemImage: "square.grid.2x2")
            }
        }
        .navigationTitle("Collage")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { PhotosPicker("Photos", selection: $items, maxSelectionCount: 9, matching: .images) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", systemImage: "square.and.arrow.down") { Task { await save() } }.disabled(shown == nil)
            }
        }
        .onChange(of: items) { _, new in Task { await load(new) } }
        .alert("Saved", isPresented: $saved) {}
    }

    private func load(_ new: [PhotosPickerItem]) async {
        var imgs: [CIImage] = []
        for item in new { if let d = try? await item.loadTransferable(type: Data.self), let i = CIImage(data: d, options: [.applyOrientationProperty: true]) { imgs.append(i) } }
        photos = imgs
        guard imgs.count >= 2, let layout = CollageLayout.autoPick(photoAspects: imgs.map { Double($0.extent.width / $0.extent.height) }) else { state = nil; shown = nil; return }
        state = CollageState(layout: layout, photoCount: imgs.count)
        redraw()
    }

    private func redraw() {
        guard let state else { return }
        let img = CollageRenderer.render(state, photos: photos.map { Renderer.proxy($0, maxDimension: 1200) }, width: 900)
        shown = CIContext().createCGImage(img, from: img.extent)
    }

    private func save() async {
        guard let state else { return }
        let img = CollageRenderer.render(state, photos: photos, width: 2400)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let data = CIContext().jpegRepresentation(of: img, colorSpace: space) else { return }
        if (try? await saver.save(data)) != nil { saved = true }
    }
}
