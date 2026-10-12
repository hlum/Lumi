import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case home = "Home", camera = "Camera", video = "Video", projects = "Projects", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: "house"
        case .camera: "camera"
        case .video: "film"
        case .projects: "folder"
        case .settings: "gearshape"
        }
    }
    /// Camera and video open from Home; the bar carries the three everyday places.
    static let bar: [RootTab] = [.home, .projects, .settings]
}

struct RootTabView: View {
    @State private var route = AppRoute.shared
    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch route.tab {
                case .camera: NavigationStack { CameraView() }
                case .video: NavigationStack { VideoEditorView() }
                case .projects: NavigationStack { ProjectsView().navigationTitle("Projects") }
                case .settings: NavigationStack { SettingsView() }
                case .home: NavigationStack { HomeView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !route.barHidden { bar.transition(.opacity) }
        }
        .background(LumiColor.ground.ignoresSafeArea())
    }

    private var bar: some View {
        HStack(spacing: 6) {
            ForEach(RootTab.bar) { tab in
                let on = route.tab == tab
                Button { route.tab = tab } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.symbol).font(.system(size: 20, weight: .regular))
                        Text(LocalizedStringKey(tab.rawValue)).font(LumiFont.tab())
                    }
                    .frame(width: 84, height: 50)
                    .foregroundStyle(on ? LumiColor.onSelectedPill : LumiColor.text.opacity(0.8))
                    .background(Capsule().fill(on ? LumiColor.selectedPill : .clear))
                }
                .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8).frame(height: 64).lumiGlass().padding(.bottom, 10)
    }
}
