import SwiftUI

struct HomeView: View {
    @State private var query = ""
    var body: some View {
        let results = ToolCatalog.search(query)
        List {
            if query.isEmpty {
                ForEach(ToolCatalog.grouped(results), id: \.0) { category, tools in
                    Section(category.rawValue.capitalized) { ForEach(tools) { Label($0.name, systemImage: $0.symbol) } }
                }
            } else {
                ForEach(results) { Label($0.name, systemImage: $0.symbol) }
            }
        }
        .searchable(text: $query, prompt: "Search tools")
        .overlay { if results.isEmpty { ContentUnavailableView.search(text: query) } }
        .navigationTitle("Tools")
    }
}
