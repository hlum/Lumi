import SwiftUI

/// Every tool, searchable (the design's "All tools").
struct ToolsView: View {
    @State private var query = ""
    var body: some View {
        let results = ToolCatalog.search(query)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if query.isEmpty {
                    ForEach(ToolCatalog.grouped(results), id: \.0) { category, tools in
                        Text(LocalizedStringKey(category.rawValue.capitalized)).font(LumiFont.section()).padding(.top, 10)
                        ForEach(tools) { row($0) }
                    }
                } else {
                    if !results.isEmpty { Text("Tools").font(LumiFont.section()).padding(.top, 6); ForEach(results) { row($0) } }
                    let recipes = RecipeLibrary().mine.filter { $0.name.localizedCaseInsensitiveContains(query) } + RecipeStore.starters.filter { $0.name.localizedCaseInsensitiveContains(query) }
                    if !recipes.isEmpty {
                        Text("Recipes").font(LumiFont.section()).padding(.top, 6)
                        ForEach(recipes) { r in NavigationLink { RecipesView() } label: { HomeRow(symbol: "wand.and.stars", title: LocalizedStringKey(r.name)) }.buttonStyle(.plain) }
                    }
                    let materials = MaterialCatalog.bundled().items(query: query).prefix(8)
                    if !materials.isEmpty {
                        Text("Materials").font(LumiFont.section()).padding(.top, 6)
                        ForEach(Array(materials)) { m in NavigationLink { MaterialsView() } label: { HomeRow(symbol: "square.grid.3x3", title: LocalizedStringKey(m.name)) }.buttonStyle(.plain) }
                    }
                }
            }.padding(.horizontal, LumiShape.margin).padding(.bottom, 24)
        }
        .background(LumiColor.ground.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search tools")
        .overlay { if results.isEmpty && !query.isEmpty && RecipeStore.starters.allSatisfy({ !$0.name.localizedCaseInsensitiveContains(query) }) && MaterialCatalog.bundled().items(query: query).isEmpty { ContentUnavailableView.search(text: query) } }
        .navigationTitle("All tools")
    }

    @ViewBuilder private func row(_ t: ToolInfo) -> some View {
        NavigationLink { destination(t) } label: { HomeRow(symbol: t.symbol, title: LocalizedStringKey(t.name)) }.buttonStyle(.plain)
    }

    static func editorTool(for id: String) -> EditorTool? {
        switch id { case "adjust": .adjust; case "crop": .crop; case "text": .text; case "remove": .remove; case "cutout": .cutout; case "enhance": .enhance; case "restore": .enhance; case "expand": .expand; case "retouch": .autoBeauty; default: nil }
    }

    @ViewBuilder private func destination(_ t: ToolInfo) -> some View {
        switch t.id {
        case "recipes": RecipesView()
        case "collage": CollageView()
        case "id-photo": IDPhotoView()
        case "scanner": ScannerView()
        case "gif": GIFMakerView()
        case "stitch": StitchView()
        case "wallpaper": WallpaperView()
        case "materials": MaterialsView()
        case "batch-cutout": BatchCutoutView()
        case "ai-create": AICreateView()
        default: EditorView(startTool: Self.editorTool(for: t.id))
        }
    }
}

/// A white list row with an icon well and a chevron.
struct HomeRow: View {
    var symbol: String
    var title: LocalizedStringKey
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(LumiColor.accentText)
                .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: LumiShape.iconWell, style: .continuous).fill(LumiColor.accentSoft))
            Text(title).font(LumiFont.headline()).foregroundStyle(LumiColor.text).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(LumiColor.textSecondary)
        }
        .padding(.horizontal, 16).frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: LumiShape.tile, style: .continuous).fill(LumiColor.surface))
        .accessibilityElement(children: .combine)
    }
}
