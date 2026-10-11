import SwiftUI

struct CameraView: View {
    @State private var camera = CameraController()
    @State private var countdown = Countdown(seconds: 0)
    @State private var shown = 0
    @State private var message: String?
    private let saver = LibraryPhotoSaver()

    var body: some View {
        ZStack(alignment: .bottom) {
            if camera.authorized {
                MetalPreviewView(image: camera.latestFrame).ignoresSafeArea(edges: .top)
                if camera.settings.showGrid { GridLines() }
            } else {
                ContentUnavailableView("Camera access needed", systemImage: "camera", description: Text("Allow the camera in Settings to take photos."))
            }
            VStack {
                if shown > 0 { Text("\\(shown)").font(.system(size: 96, weight: .bold)).foregroundStyle(.white).shadow(radius: 8) }
                Spacer()
                controls
            }.padding()
        }
        .navigationTitle("Camera")
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .overlay(alignment: .top) { if let message { Text(message).padding(8).background(.thinMaterial, in: Capsule()) } }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button(camera.settings.flash.rawValue.capitalized, systemImage: "bolt.fill") { camera.settings.cycleFlash() }
                Button("\\(camera.settings.timer)s", systemImage: "timer") { camera.settings.cycleTimer() }
                Button("Grid", systemImage: "grid") { camera.settings.showGrid.toggle() }
                Button(camera.settings.aspect.rawValue) { let all = CameraSettings.Aspect.allCases; camera.settings.aspect = all[((all.firstIndex(of: camera.settings.aspect) ?? 0) + 1) % all.count] }
                Button("Flip", systemImage: "arrow.triangle.2.circlepath.camera") { camera.settings.flip() }
            }.labelStyle(.iconOnly).buttonStyle(.bordered)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("None") { camera.settings.lookID = nil }.buttonStyle(.bordered)
                    ForEach(FilterLibrary.shared.entries.prefix(12)) { e in
                        Button(LocalizedStringKey(e.name)) { camera.settings.lookID = e.id }.buttonStyle(.bordered)
                    }
                }
            }
            Slider(value: Binding(get: { camera.settings.beauty }, set: { camera.settings.beauty = $0 }), in: 0...1)
            Button { Task { await shoot() } } label: { Circle().fill(.white).frame(width: 70, height: 70).overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 4)) }
                .accessibilityLabel("Shutter")
        }
    }

    private func shoot() async {
        var cd = Countdown(seconds: camera.settings.timer); cd.start()
        shown = cd.remaining
        while cd.isRunning { try? await Task.sleep(for: .seconds(1)); let fire = cd.tick(); shown = cd.remaining; if fire { break } }
        shown = 0
        guard let data = await camera.capture() else { message = "Couldn't take the photo"; return }
        do { try await saver.save(data); message = "Saved" } catch { message = "Couldn't save" }
        try? await Task.sleep(for: .seconds(1.5)); message = nil
    }
}

private struct GridLines: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                for i in 1...2 {
                    let x = g.size.width * CGFloat(i) / 3, y = g.size.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: g.size.height))
                    p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: g.size.width, y: y))
                }
            }.stroke(.white.opacity(0.5), lineWidth: 0.5)
        }.allowsHitTesting(false)
    }
}
