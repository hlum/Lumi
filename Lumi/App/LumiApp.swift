import SwiftData
import SwiftUI

@main
struct LumiApp: App {
    init() { FontLibrary.registerBundled(); Renderer.services.subjectMasker = VisionSubjectMasker(); Renderer.services.faceFinder = VisionFaceFinder(); if SiggraphColorizer.isModelAvailable { Renderer.services.colorizer = LazyColorizer() }; if RealESRGANUpscaler.isModelAvailable { Renderer.services.upscaler = LazyUpscaler() }; if LaMaInpainter.isModelAvailable { Renderer.services.inpainter = LazyInpainter() } }

    var body: some Scene {
        WindowGroup { RootTabView() }.modelContainer(for: Project.self)
    }
}
