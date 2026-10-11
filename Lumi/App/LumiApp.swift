import SwiftData
import SwiftUI

@main
struct LumiApp: App {
    init() { FontLibrary.registerBundled(); Renderer.services.subjectMasker = VisionSubjectMasker(); if LaMaInpainter.isModelAvailable { Renderer.services.inpainter = LazyInpainter() } }

    var body: some Scene {
        WindowGroup { RootTabView() }.modelContainer(for: Project.self)
    }
}
