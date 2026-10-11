import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    var body: some View {
        if projects.isEmpty {
            ContentUnavailableView("No drafts yet", systemImage: "square.stack", description: Text("Edits you start appear here."))
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                    ForEach(projects) { p in
                        Group {
                            if let d = p.thumbnail, let ui = UIImage(data: d) { Image(uiImage: ui).resizable().scaledToFill() }
                            else { Color.secondary.opacity(0.2) }
                        }
                        .frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding()
            }
        }
    }
}
