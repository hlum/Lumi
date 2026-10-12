import PhotosUI
import SwiftUI

struct EditorRoute: Hashable, Identifiable {
    let id = UUID()
    var data: Data
    var tool: EditorTool?
}

/// Home: pick a photo, jump to a tool, or fix something fast.
struct HomeView: View {
    @State private var heroItem: PhotosPickerItem?
    @State private var fixItem: PhotosPickerItem?
    @State private var fixTool: EditorTool = .face
    @State private var route: EditorRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Lumi").font(LumiFont.largeTitle())
                    Spacer()
                    NavigationLink { ToolsView() } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .semibold)).foregroundStyle(LumiColor.text)
                            .frame(width: 44, height: 44).background(Circle().fill(LumiColor.surface)).shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    }.accessibilityLabel("Search tools")
                }
                hero.padding(.top, 18)
                HStack(spacing: 10) {
                    tile("camera", "Camera") { CameraView() }
                    tile("square.grid.2x2", "Collage") { CollageView() }
                    tile("film", "Video") { VideoEditorView() }
                    tile("ellipsis", "All tools") { ToolsView() }
                }.padding(.top, 12)
                Text("Quick fixes").font(LumiFont.section()).padding(.top, 24).padding(.bottom, 12)
                VStack(spacing: 10) {
                    fix("face.dashed", "Retouch a face", .face)
                    fix("eraser", "Remove people or objects", .remove)
                    fix("sparkles", "Sharpen a blurry photo", .enhance)
                }
            }
            .padding(.horizontal, LumiShape.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .background(LumiColor.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $route) { r in EditorView(initial: r.data, startTool: r.tool) }
        .onChange(of: heroItem) { _, new in go(new, tool: nil) }
        .onChange(of: fixItem) { _, new in go(new, tool: fixTool) }
    }

    private var hero: some View {
        PhotosPicker(selection: $heroItem, matching: .images) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer()
                Text("Edit a photo").font(LumiFont.title())
                Text("Pick from your library").font(LumiFont.body())
            }
            .foregroundStyle(LumiColor.onAccent)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .bottomLeading).padding(20)
            .background(RoundedRectangle(cornerRadius: LumiShape.photo, style: .continuous).fill(LumiColor.accent))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 54)).foregroundStyle(LumiColor.onAccent.opacity(0.5)).padding(22)
            }
        }
        .buttonStyle(.plain)
    }

    private func tile<D: View>(_ symbol: String, _ title: LocalizedStringKey, @ViewBuilder _ destination: @escaping () -> D) -> some View {
        NavigationLink { destination().toolbar(.hidden, for: .tabBar) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(LumiColor.accentText)
                Text(title).font(LumiFont.caption()).foregroundStyle(LumiColor.text).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: LumiShape.tile, style: .continuous).fill(LumiColor.surface))
        }
        .buttonStyle(.plain)
    }

    private func fix(_ symbol: String, _ title: LocalizedStringKey, _ tool: EditorTool) -> some View {
        PhotosPicker(selection: Binding(get: { nil }, set: { fixTool = tool; fixItem = $0 }), matching: .images) {
            HomeRow(symbol: symbol, title: title)
        }.buttonStyle(.plain)
    }

    private func go(_ item: PhotosPickerItem?, tool: EditorTool?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) { route = EditorRoute(data: data, tool: tool) }
            heroItem = nil; fixItem = nil
        }
    }
}
