import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @State private var selecting = false
    @State private var picked: Set<UUID> = []

    private var store: ProjectStore { ProjectStore(context: context, directory: ProjectStore.defaultDirectory) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Projects").font(LumiFont.largeTitle())
                    Spacer()
                    if !projects.isEmpty { Button(selecting ? "Done" : "Select") { selecting.toggle(); picked = [] }.font(LumiFont.chip()).foregroundStyle(LumiColor.accentText).frame(minWidth: 44, minHeight: 44) }
                }
                if projects.isEmpty {
                    VStack(spacing: 10) { Image(systemName: "folder").font(.system(size: 42)); Text("No drafts yet").font(LumiFont.headline()); Text("Edits you start appear here.").font(.footnote) }
                        .foregroundStyle(LumiColor.textSecondary).frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                        ForEach(projects) { p in cell(p) }
                    }
                    if selecting, !picked.isEmpty {
                        Button(role: .destructive) { for p in projects where picked.contains(p.id) { try? store.delete(p) }; picked = []; selecting = false } label: {
                            Text("Delete \(picked.count)").font(LumiFont.chip()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(.white).background(Capsule().fill(LumiColor.destructive))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, LumiShape.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .background(LumiColor.ground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func cell(_ p: Project) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let d = p.thumbnail, let ui = UIImage(data: d) { Image(uiImage: ui).resizable().scaledToFill() } else { LumiColor.well }
                }
                .frame(height: 170).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: LumiShape.tile, style: .continuous))
                if selecting { Image(systemName: picked.contains(p.id) ? "checkmark.circle.fill" : "circle").font(.system(size: 24)).foregroundStyle(picked.contains(p.id) ? LumiColor.accent : .white).padding(8).shadow(radius: 2) }
            }
            Text(caption(p.updatedAt)).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(LumiColor.textSecondary)
        }
        if selecting {
            Button { if picked.contains(p.id) { picked.remove(p.id) } else { picked.insert(p.id) } } label: { content }.buttonStyle(.plain)
        } else {
            NavigationLink { EditorView(project: p) } label: { content }.buttonStyle(.plain)
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") { _ = try? store.duplicate(p) }
                    Button("Delete", systemImage: "trash", role: .destructive) { try? store.delete(p) }
                }
        }
    }

    private func caption(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Edited today" }
        if Calendar.current.isDateInYesterday(d) { return "Edited yesterday" }
        return "Edited " + d.formatted(.dateTime.month(.abbreviated).day())
    }
}
