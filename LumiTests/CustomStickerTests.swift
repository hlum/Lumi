import CoreImage
import Foundation
import Testing
@testable import Lumi

struct CustomStickerTests {
    static func store() -> CustomStickerStore { CustomStickerStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) }
    /// A red 40x30 blob inside a transparent 200x100 canvas.
    static func cutout() -> CIImage {
        CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 60, y: 30, width: 40, height: 30))
            .composited(over: CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100)))
    }

    @Test func visibleBoundsFindTheBlob() throws {
        let b = try #require(CustomStickerStore.visibleBounds(Self.cutout()))
        #expect(b == CGRect(x: 60, y: 30, width: 40, height: 30))
        #expect(CustomStickerStore.visibleBounds(CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20))) == nil)
    }

    @Test func addedStickersAreTrimmedAndComeBackAsImages() throws {
        let s = Self.store()
        let m = try #require(s.add(cutout: Self.cutout(), name: "Blob"))
        #expect(CustomStickerStore.isCustom(m.id) && m.name == "Blob" && s.items.count == 1)
        let img = try #require(s.image(m.id))
        #expect(img.extent.width <= 44 && img.extent.height <= 34 && img.extent.width >= 40)                // trimmed to the blob plus a hair of margin
        #expect(GeometryTests.rgb(img, x: Int(img.extent.width) / 2, y: Int(img.extent.height) / 2)[0] > 200)
    }

    @Test func fullyTransparentPicturesAreRejected() {
        #expect(Self.store().add(cutout: CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 10))) == nil)
    }

    @Test func stickersPersistAcrossLaunchesAndCanBeRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = CustomStickerStore(directory: dir)
        let m = try #require(a.add(cutout: Self.cutout()))
        let b = CustomStickerStore(directory: dir)
        #expect(b.items.map(\.id) == [m.id] && b.image(m.id) != nil)
        b.remove(m.id)
        #expect(CustomStickerStore(directory: dir).items.isEmpty && b.image(m.id) == nil)
    }

    @Test func unknownOrBuiltInIdsAreNotCustom() {
        let s = Self.store()
        #expect(s.image("custom-nope") == nil && s.image("heart") == nil && !CustomStickerStore.isCustom("heart"))
    }

    @Test func aCustomStickerRendersLikeAnyOtherLayer() throws {
        let saved = CustomStickerStore.shared
        defer { CustomStickerStore.shared = saved }
        let s = Self.store(); CustomStickerStore.shared = s
        let m = try #require(s.add(cutout: Self.cutout()))
        var stack = LayerStack(); try stack.add(Layer(content: .sticker(id: m.id, outline: 0)))
        let base = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let out = LayerRenderer.render(stack, over: base)
        #expect((60..<140).contains { x in (60..<140).contains { y in GeometryTests.rgb(out, x: x, y: y)[0] > 200 } })     // the red blob appears mid-photo
    }
}

extension ServicesSerial {
struct CustomStickerSubjectTests {
    @MainActor @Test func makeFromSubjectUsesTheSubjectDetector() throws {
        let saved = CustomStickerStore.shared; defer { CustomStickerStore.shared = saved; Renderer.services = Renderer.Services() }
        let s = CustomStickerTests.store(); CustomStickerStore.shared = s
        Renderer.services = Renderer.Services(); Renderer.services.subjectMasker = FakeMasker()
        let m = EditorModel(saver: EditorModelTests.FakeSaver())
        m.load(image: CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100)))
        let made = try #require(m.makeStickerFromSubject())
        let img = try #require(s.image(made.id))
        #expect(img.extent.width <= 110 && img.extent.width >= 90)                                          // FakeMasker's subject is the left half
        Renderer.services = Renderer.Services()
        #expect(m.makeStickerFromSubject() == nil)                                                          // no detector: nothing made
    }
}
}
