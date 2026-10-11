import SwiftData
import SwiftUI

@main
struct LumiApp: App {
    init() { if LaMaInpainter.isModelAvailable { Renderer.services.inpainter = LazyInpainter() } }

    var body: some Scene {
        WindowGroup { RootTabView() }.modelContainer(for: Project.self)
    }
}
