import SwiftData
import SwiftUI

@main
struct LumiApp: App {
    init() { FontLibrary.registerBundled(); Renderer.services.subjectMasker = VisionSubjectMasker(); Renderer.services.faceFinder = VisionFaceFinder(); Renderer.services.textFinder = VisionTextFinder(); Renderer.services.peopleFinder = VisionPeopleFinder(); Renderer.services.objectFinder = VisionObjectFinder(); Renderer.services.hairMasker = AdaptiveHairMasker(estimate: EstimatedHairMasker(faces: VisionFaceLandmarker(), subject: VisionSubjectMasker())); Renderer.services.faceLandmarker = VisionFaceLandmarker(); Renderer.services.bodyFinder = VisionBodyFinder(); Renderer.services.handFinder = VisionHandFinder(); Renderer.services.colorizer = LazyColorizer(); Renderer.services.upscaler = LazyUpscaler(); Renderer.services.inpainter = LazyInpainter() }

    var body: some Scene {
        WindowGroup { RootTabView().tint(LumiColor.accent).fontDesign(.rounded) }.modelContainer(for: Project.self)
    }
}
