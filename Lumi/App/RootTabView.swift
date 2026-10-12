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
    /// Camera and video open from Home (and from Shortcuts); the system tab bar carries the everyday places.
    static let bar: [RootTab] = [.home, .projects, .settings]
}

/// The system tab bar: on iOS 26 it is the Liquid Glass bar, nothing custom drawn.
struct RootTabView: View {
    @State private var route = AppRoute.shared
    var body: some View {
        TabView(selection: $route.tab) {
            Tab(RootTab.home.rawValue, systemImage: RootTab.home.symbol, value: RootTab.home) { NavigationStack { HomeView() } }
            Tab(RootTab.projects.rawValue, systemImage: RootTab.projects.symbol, value: RootTab.projects) { NavigationStack { ProjectsView().navigationTitle("Projects") } }
            Tab(RootTab.settings.rawValue, systemImage: RootTab.settings.symbol, value: RootTab.settings) { NavigationStack { SettingsView() } }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Shortcuts ask for the camera or video tab: show them over the bar, outside it
        .fullScreenCover(isPresented: Binding(get: { route.tab == .camera || route.tab == .video }, set: { if !$0 { route.tab = .home } })) {
            NavigationStack { route.tab == .video ? AnyView(VideoEditorView()) : AnyView(CameraView()) }
        }
    }
}
