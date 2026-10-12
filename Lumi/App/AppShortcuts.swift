import SwiftUI
import AppIntents
import Observation

/// Where an outside request (Shortcuts, Siri, a widget link) wants the app to go.
@Observable
final class AppRoute {
    nonisolated(unsafe) static let shared = AppRoute()
    var tab = RootTab.home
    var pendingTool: String?          // ToolCatalog id the Home screen should open, then clear

    func openCamera() { tab = .camera; pendingTool = nil }
    func openTool(_ id: String) { tab = .home; pendingTool = id }
    func consumeTool() -> String? { defer { pendingTool = nil }; return pendingTool }
}

struct OpenCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Camera"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { AppRoute.shared.openCamera(); return .result() }
}

struct OpenRemoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Objects"
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult { AppRoute.shared.openTool("remove"); return .result() }
}

struct LumiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenCameraIntent(), phrases: ["Open camera in \(.applicationName)", "Take a photo with \(.applicationName)"], shortTitle: "Camera", systemImageName: "camera")
        AppShortcut(intent: OpenRemoverIntent(), phrases: ["Remove objects in \(.applicationName)", "Open remover in \(.applicationName)"], shortTitle: "Remover", systemImageName: "eraser")
    }
}

