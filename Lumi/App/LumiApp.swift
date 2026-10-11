import SwiftData
import SwiftUI

@main
struct LumiApp: App {
    var body: some Scene {
        WindowGroup { RootTabView() }.modelContainer(for: Project.self)
    }
}
