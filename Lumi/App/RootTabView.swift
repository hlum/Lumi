import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case home = "Home", camera = "Camera", video = "Video", projects = "Projects", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: "house"
        case .camera: "camera"
        case .video: "film"
        case .projects: "square.stack"
        case .settings: "gearshape"
        }
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            ForEach(RootTab.allCases) { tab in
                Tab(tab.rawValue, systemImage: tab.symbol) {
                    NavigationStack {
                        if tab == .home { HomeView() }
                        else if tab == .camera { CameraView() }
                        else if tab == .video { VideoEditorView() }
                        else if tab == .projects { ProjectsView().navigationTitle("Projects") }
                        else if tab == .settings { SettingsView() }
                        else { ContentUnavailableView(tab.rawValue, systemImage: tab.symbol).navigationTitle(tab.rawValue) }
                    }
                }
            }
        }
    }
}
