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
                    ForEach(results) { row($0) }
                }
            }.padding(.horizontal, LumiShape.margin).padding(.bottom, 24)
        }
        .background(LumiColor.ground.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search tools")
        .overlay { if results.isEmpty { ContentUnavailableView.search(text: query) } }
        .navigationTitle("All tools")
    }

    @ViewBuilder private func row(_ t: ToolInfo) -> some View {
        NavigationLink { destination(t) } label: { HomeRow(symbol: t.symbol, title: LocalizedStringKey(t.name)) }.buttonStyle(.plain)
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
        default: EditorView()
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
