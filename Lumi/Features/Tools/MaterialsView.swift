import SwiftUI

/// Everything bundled: stickers, filters, fonts, frames and backgrounds, with search, collections and favourites.
struct MaterialsView: View {
    @State private var catalog = MaterialCatalog.bundled()
    @State private var kind: Material.Kind?
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var storage = CacheManager.standard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Search materials", text: $query).lumiField()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        LumiChip(title: "All", selected: kind == nil && !favoritesOnly) { kind = nil; favoritesOnly = false }
                        LumiChip(title: "My materials", selected: favoritesOnly, symbol: "star") { favoritesOnly.toggle() }
                        ForEach(Material.Kind.allCases, id: \.self) { k in LumiChip(title: Self.title(k), selected: kind == k) { kind = k; favoritesOnly = false } }
                    }
                }
                if query.isEmpty && kind == nil && !favoritesOnly && !catalog.collections.isEmpty {
                    Text("Collections").font(LumiFont.section())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(catalog.collections) { c in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(LumiFont.headline())
                                    Text(c.isSeasonal ? "Seasonal" : "Collection").font(.footnote).foregroundStyle(LumiColor.textSecondary)
                                }.padding(14).frame(width: 150, alignment: .leading).background(RoundedRectangle(cornerRadius: LumiShape.tile, style: .continuous).fill(LumiColor.surface))
                            }
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
                    ForEach(shown) { m in tile(m) }
                }
                if shown.isEmpty { ContentUnavailableView(favoritesOnly ? "Nothing starred yet" : "Nothing found", systemImage: "square.grid.2x2").padding(.top, 30) }
                NavigationLink { WallpaperView() } label: { HomeRow(symbol: "iphone", title: "Make a wallpaper") }.buttonStyle(.plain)
                NavigationLink { CreditsView() } label: { HomeRow(symbol: "heart", title: "See credits for every material") }.buttonStyle(.plain)
            }
            .padding(.horizontal, LumiShape.margin).padding(.vertical, 8)
        }
        .background(LumiColor.ground.ignoresSafeArea())
        .navigationTitle("Materials")
    }

    private var shown: [Material] {
        favoritesOnly ? catalog.mine.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } : catalog.items(kind: kind, query: query)
    }

    private static func title(_ k: Material.Kind) -> LocalizedStringKey {
        switch k { case .sticker: "Stickers"; case .filter: "Filters"; case .font: "Fonts"; case .frame: "Frames"; case .background: "Backgrounds" }
    }

    private func tile(_ m: Material) -> some View {
        Button { catalog.toggleFavorite(m) } label: {
            VStack(spacing: 6) {
                preview(m).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(m.name).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(LumiColor.text).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LumiColor.surface))
            .overlay(alignment: .topTrailing) { if catalog.favorites.contains(m.id) { Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(LumiColor.accent).padding(8) } }
        }
        .buttonStyle(.plain).accessibilityHint("Double tap to star").accessibilityAddTraits(catalog.favorites.contains(m.id) ? .isSelected : [])
    }

    @ViewBuilder private func preview(_ m: Material) -> some View {
        switch m.kind {
        case .sticker:
            if let ci = StickerLibrary.image(m.itemID, side: 128), let cg = CIContext().createCGImage(ci, from: ci.extent) { Image(decorative: cg, scale: 1).resizable().scaledToFit().padding(6).background(LumiColor.well) } else { LumiColor.well }
        case .font: ZStack { LumiColor.well; Text("Aa").font(.custom(m.itemID, size: 28)).foregroundStyle(LumiColor.text) }
        case .background: if let b = BackgroundSwatch.all.first(where: { $0.id == m.itemID }) { Color(red: b.color.r, green: b.color.g, blue: b.color.b) } else { LumiColor.well }
        case .frame: ZStack { LumiColor.well; RoundedRectangle(cornerRadius: 6).stroke(LumiColor.text, lineWidth: 6).padding(10) }
        case .filter: ZStack { LinearGradient(colors: [.orange.opacity(0.7), .pink.opacity(0.6), .indigo.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "camera.filters").foregroundStyle(.white) }
        }
    }
}
