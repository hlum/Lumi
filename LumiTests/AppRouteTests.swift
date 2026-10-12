import Testing
@testable import Lumi

struct AppRouteTests {
    @Test func cameraRequestSelectsTheCameraTab() {
        let r = AppRoute(); r.openTool("remove"); r.openCamera()
        #expect(r.tab == .camera && r.pendingTool == nil)
    }

    @Test func toolRequestGoesHomeAndIsConsumedOnce() {
        let r = AppRoute(); r.tab = .settings; r.openTool("remove")
        #expect(r.tab == .home && r.pendingTool == "remove")
        #expect(r.consumeTool() == "remove" && r.consumeTool() == nil)
    }

    @Test func shortcutsAreRegistered() {
        #expect(LumiShortcuts.appShortcuts.count == 2)
    }
}
