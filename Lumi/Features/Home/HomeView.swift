import SwiftUI

struct HomeView: View {
    @State private var query = ""
    var body: some View {
        let results = ToolCatalog.search(query)
        List {
            if query.isEmpty {
                ForEach(ToolCatalog.grouped(results), id: \.0) { category, tools in
                    Section(category.rawValue.capitalized) { ForEach(tools) { row($0) } }
                }
            } else {
                ForEach(results) { row($0) }
            }
        }
        .searchable(text: $query, prompt: "Search tools")
        .overlay { if results.isEmpty { ContentUnavailableView.search(text: query) } }
        .navigationTitle("Tools")
    }

    @ViewBuilder private func row(_ t: ToolInfo) -> some View {
        switch t.id {
        case "collage": NavigationLink { CollageView() } label: { Label(LocalizedStringKey(t.name), systemImage: t.symbol) }
        default: NavigationLink { EditorView() } label: { Label(LocalizedStringKey(t.name), systemImage: t.symbol) }
        }
    }
}
