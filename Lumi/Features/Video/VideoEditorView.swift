import AVKit
import PhotosUI
import SwiftUI

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

struct VideoEditorView: View {
    @State private var model = VideoEditorModel()
    @State private var items: [PhotosPickerItem] = []
    @State private var player = AVPlayer()
    @State private var exported: URL?

    var body: some View {
        VStack(spacing: 8) {
            if model.timeline.isEmpty {
                ContentUnavailableView("Add clips", systemImage: "film", description: Text("Pick videos or photos to start."))
            } else {
                VideoPlayer(player: player).frame(maxHeight: 280)
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(model.timeline.clips) { clip in
                            let isSelected = model.selected == clip.id
                            VStack {
                                Image(systemName: clip.isPhoto ? "photo" : "video")
                                Text(String(format: "%.1fs", clip.duration)).font(.caption2)
                                if clip.transition != .none { Text(clip.transition.rawValue).font(.caption2) }
                            }
                            .frame(width: 70, height: 60).background(isSelected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { model.selected = clip.id }
                        }
                    }.padding(.horizontal)
                }
                Slider(value: Binding(get: { model.playhead }, set: { model.seek($0); player.seek(to: CMTime(seconds: model.playhead, preferredTimescale: 600)) }), in: 0...max(model.timeline.duration, 0.1))
                    .padding(.horizontal)
                HStack {
                    Button("Split", systemImage: "scissors") { model.splitAtPlayhead() }
                    Button("Duplicate", systemImage: "plus.square.on.square") { model.duplicateSelected() }
                    Button("Delete", systemImage: "trash") { model.deleteSelected() }
                    Menu("Speed", systemImage: "speedometer") { ForEach([0.5, 1, 1.5, 2, 4], id: \.self) { s in Button("\(s, specifier: "%g")×") { model.setSpeed(s) } } }
                    Menu("Transition", systemImage: "rectangle.on.rectangle") { ForEach(TransitionKind.allCases, id: \.self) { k in Button(k.rawValue.capitalized) { model.setTransition(k) } } }
                }.labelStyle(.iconOnly).buttonStyle(.bordered).disabled(model.selected == nil)
            }
            if let e = model.error { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .navigationTitle("Video")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { PhotosPicker("Add", selection: $items, matching: .any(of: [.videos, .images])) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.canRedo)
                if let exported { ShareLink(item: exported) }
                Button(model.isExporting ? "Exporting…" : "Export", systemImage: "square.and.arrow.up") { Task { exported = await model.exportVideo() } }.disabled(model.timeline.isEmpty || model.isExporting)
            }
        }
        .onChange(of: items) { _, new in
            Task {
                for item in new {
                    if let m = try? await item.loadTransferable(type: PickedMovie.self) { await model.addVideo(m.url) }
                    else if let d = try? await item.loadTransferable(type: Data.self), let img = CIImage(data: d, options: [.applyOrientationProperty: true]) { await model.addPhoto(img) }
                }
                items = []
            }
        }
        .onChange(of: model.playerItem) { _, item in player.replaceCurrentItem(with: item) }
    }
}
