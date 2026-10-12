import SwiftData
import SwiftUI

@main
struct LumiApp: App {
    init() { FontLibrary.registerBundled(); Renderer.services.subjectMasker = AdaptiveSubjectMasker(fallback: VisionSubjectMasker()); Renderer.services.faceFinder = VisionFaceFinder(); Renderer.services.textFinder = VisionTextFinder(); Renderer.services.peopleFinder = VisionPeopleFinder(); Renderer.services.objectFinder = VisionObjectFinder(); Renderer.services.hairMasker = AdaptiveHairMasker(estimate: EstimatedHairMasker(faces: VisionFaceLandmarker(), subject: VisionSubjectMasker())); Renderer.services.faceLandmarker = VisionFaceLandmarker(); Renderer.services.bodyFinder = VisionBodyFinder(); Renderer.services.handFinder = VisionHandFinder(); Renderer.services.colorizer = LazyColorizer(); Renderer.services.upscaler = LazyUpscaler(); Renderer.services.inpainter = LazyInpainter() }

    @AppStorage("look.appearance") private var appearance = AppPrefs.Appearance.system.rawValue
    private var scheme: ColorScheme? { switch AppPrefs.Appearance(rawValue: appearance) ?? .system { case .system: nil; case .light: .light; case .dark: .dark } }

    var body: some Scene {
        WindowGroup { RootTabView().tint(LumiColor.accent).fontDesign(.rounded).preferredColorScheme(scheme) }.modelContainer(for: Project.self)
    }
}
