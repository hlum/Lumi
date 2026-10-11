import SwiftData
import SwiftUI

@main
struct LumiApp: App {
    init() { Renderer.services.subjectMasker = VisionSubjectMasker(); if LaMaInpainter.isModelAvailable { Renderer.services.inpainter = LazyInpainter() } }

    var body: some Scene {
        WindowGroup { RootTabView() }.modelContainer(for: Project.self)
    }
}
