import CoreImage
import Foundation
import Testing
@testable import Lumi

struct ModelStoreTests {
    private func makeStore(bundled: [ModelEntry] = []) throws -> (ModelStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("models-" + UUID().uuidString)
        // an empty bundle: nothing is "bundled" unless a test puts a fake file where the store looks
        return (ModelStore(bundle: Bundle(for: BundleToken.self), directory: dir, defaults: bundled), dir)
    }
    private final class BundleToken {}

    private func fakeInstalled(_ id: String, slot: ModelSlot, in store: ModelStore, version: String = "1") throws -> ModelEntry {
        var e = ModelEntry(id: id, slot: slot, title: id, version: version, file: "\(id)-\(version).mlmodelc", io: Dictionary(uniqueKeysWithValues: (slot.inputRoles + slot.outputRoles).map { ($0, $0) }))
        e.bundled = false
        try FileManager.default.createDirectory(at: store.installedDirectory.appendingPathComponent(e.file), withIntermediateDirectories: true)
        store.adopt(e)
        return e
    }

    @Test func defaultsDescribeTheBundledModels() {
        let d = ModelEntry.bundledDefaults
        #expect(Set(d.map(\.slot)) == [.inpaint, .upscale, .colorize, .hairSegmentation, .personMatting])
        for e in d { #expect(e.bundled && e.missingRoles.isEmpty && e.file.hasSuffix(".mlmodelc"), "\(e.id)") }
        #expect(d.first { $0.slot == .inpaint }?.side == 800 && d.first { $0.slot == .upscale }?.scale == 4)
    }

    @Test func nothingIsActiveWhenNoFileExists() throws {
        let (store, _) = try makeStore(bundled: ModelEntry.bundledDefaults)        // the test bundle has no LaMa
        #expect(store.active(.inpaint) == nil && !store.isAvailable(.inpaint) && store.entries(.upscale).isEmpty)
        #expect(throws: ModelStoreError.self) { try store.load(.inpaint) }
    }

    @Test func aNewlyAddedModelBecomesActiveAndCanBeSwitchedAndReset() throws {
        let (store, _) = try makeStore()
        let a = try fakeInstalled("better-lama", slot: .inpaint, in: store)
        #expect(store.active(.inpaint)?.id == a.id && store.isAvailable(.inpaint))
        let b = try fakeInstalled("other-lama", slot: .inpaint, in: store)
        #expect(store.active(.inpaint)?.id == b.id && store.entries(.inpaint).count == 2)
        try store.select(a.id, for: .inpaint)
        #expect(store.active(.inpaint)?.id == a.id)
        store.reset(.inpaint)                                           // no bundled one here, so the first installed takes over
        #expect(store.active(.inpaint)?.id == a.id)
        #expect(throws: ModelStoreError.self) { try store.select("nope", for: .inpaint) }
    }

    @Test func removingTheChosenModelFallsBackAndDeletesTheFile() throws {
        let (store, dir) = try makeStore()
        let a = try fakeInstalled("a", slot: .upscale, in: store), b = try fakeInstalled("b", slot: .upscale, in: store)
        #expect(store.active(.upscale)?.id == "b")
        try store.remove(b.id)
        #expect(store.active(.upscale)?.id == a.id && !FileManager.default.fileExists(atPath: dir.appendingPathComponent(b.file).path))
        #expect(throws: ModelStoreError.self) { try store.remove("b") }
    }

    @Test func choicesSurviveARestart() throws {
        let (store, dir) = try makeStore()
        let a = try fakeInstalled("keep-me", slot: .colorize, in: store)
        _ = try fakeInstalled("newer", slot: .colorize, in: store)
        try store.select(a.id, for: .colorize)
        let again = ModelStore(bundle: Bundle(for: BundleToken.self), directory: dir, defaults: [])
        #expect(again.active(.colorize)?.id == a.id && again.entries(.colorize).count == 2)
    }

    @Test func revisionChangesWheneverTheChoiceDoes() throws {
        let (store, _) = try makeStore()
        let r0 = store.revision
        let a = try fakeInstalled("x", slot: .inpaint, in: store)
        #expect(store.revision > r0)
        let r1 = store.revision
        try store.select(a.id, for: .inpaint); store.reset(.inpaint)
        #expect(store.revision >= r1 + 2)
    }

    @Test func compatibilityCheckNamesWhatIsMissing() {
        let e = ModelEntry(id: "m", slot: .inpaint, title: "m", file: "m.mlmodelc", io: ["image": "img", "mask": "msk", "output": "out"])
        #expect(ModelStore.missingFeatures(entry: e, inputs: ["img", "msk"], outputs: ["out"]).isEmpty)
        #expect(ModelStore.missingFeatures(entry: e, inputs: ["img"], outputs: []) == ["msk", "out"])
        var partial = e; partial.io["mask"] = nil
        #expect(partial.missingRoles == ["mask"])
    }

    @Test func slotsDeclareWhatTheyNeed() {
        for s in ModelSlot.allCases { #expect(!s.title.isEmpty && !s.inputRoles.isEmpty && !s.outputRoles.isEmpty && !s.hint.isEmpty) }
        #expect(ModelSlot.inpaint.inputRoles == ["image", "mask"])
    }
}

struct MaskDecodeTests {
    @Test func probabilitiesAreScaledAndLogitsSquashed() {
        #expect(MaskDecode.plane([0, 0.5, 1]) == [0, 128, 255])
        let l = MaskDecode.plane([-10, 0, 10])
        #expect(l[0] < 3 && l[1] == 128 && l[2] > 252)
        #expect(MaskDecode.plane([0.2, 0.9], looksLikeLogits: true)[0] > 128)       // forced
    }

    @Test func shapesWithChannelsPickTheRightPlane() {
        let flat: [Float] = [0, 0, 0, 0, 1, 1, 1, 1]            // two 2x2 channels
        let a = MaskDecode.extract(flat, shape: [1, 2, 2, 2], channel: 1)!
        #expect(a.plane == [1, 1, 1, 1] && a.width == 2 && a.height == 2)
        #expect(MaskDecode.extract(flat, shape: [2, 4])!.plane.count == 8)
        #expect(MaskDecode.extract(flat, shape: [1, 2, 2, 2], channel: 2) == nil && MaskDecode.extract([], shape: [3, 3]) == nil)
    }

    @Test func missingModelFallsBackToTheEstimate() throws {
        struct Fixed: HairMasking { func hairMasks(in image: CIImage) throws -> [CIImage] { [CIImage(color: .white).cropped(to: image.extent)] } }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hm-" + UUID().uuidString)
        let store = ModelStore(bundle: Bundle.main, directory: dir, defaults: [])
        let img = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20))
        #expect(!store.isAvailable(.hairSegmentation))
        #expect(try AdaptiveHairMasker(estimate: Fixed(), store: store).hairMasks(in: img).count == 1)
    }
}
