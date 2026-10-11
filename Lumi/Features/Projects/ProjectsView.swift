import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    private var store: ProjectStore { ProjectStore(context: context, directory: ProjectStore.defaultDirectory) }

    var body: some View {
        if projects.isEmpty {
            ContentUnavailableView("No drafts yet", systemImage: "square.stack", description: Text("Edits you start appear here."))
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                    ForEach(projects) { p in
                        NavigationLink { EditorView(project: p) } label: {
                        Group {
                            if let d = p.thumbnail, let ui = UIImage(data: d) { Image(uiImage: ui).resizable().scaledToFill() }
                            else { Color.secondary.opacity(0.2) }
                        }
                        .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .contextMenu {
                            Button("Duplicate", systemImage: "plus.square.on.square") { _ = try? store.duplicate(p) }
                            Button("Delete", systemImage: "trash", role: .destructive) { try? store.delete(p) }
                        }
                    }
                }.padding()
            }
        }
    }
}
