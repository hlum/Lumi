import CoreImage
import Foundation
import Observation

/// Applies a recipe to many photos, one at a time, saving each result. Failures are reported per photo.
@Observable @MainActor
final class BatchModel {
    struct Item: Identifiable, Equatable { let id = UUID(); var name: String; var status = Status.waiting
        enum Status: Equatable { case waiting, working, done, failed(String) } }

    private(set) var items: [Item] = []
    private(set) var completed = 0
    private(set) var isRunning = false
    private var cancelled = false
    static let maxCutoutPhotos = 30
    private let saver: PhotoSaving

    init(saver: PhotoSaving = LibraryPhotoSaver()) { self.saver = saver }

    var progress: Double { items.isEmpty ? 0 : Double(completed) / Double(items.count) }
    var failures: [Item] { items.filter { if case .failed = $0.status { true } else { false } } }

    /// `photos`: encoded image data with a display name each.
    func run(_ photos: [(name: String, data: Data)], recipe: Recipe, categories: Set<RecipeCategory>? = nil) async {
        items = photos.map { Item(name: $0.name) }
        completed = 0; isRunning = true; cancelled = false
        defer { isRunning = false }
        // one photo at a time keeps memory flat; a failure marks that photo and moves on
        for (i, photo) in photos.enumerated() {
            if Task.isCancelled { break }
            items[i].status = .working
            do {
                let out = try Self.render(photo.data, recipe: recipe, categories: categories)
                try await saver.save(out)
                items[i].status = .done
            } catch {
                items[i].status = .failed(String(describing: error))
            }
            completed += 1
        }
    }

    func cancel() { cancelled = true }

    /// Cuts the subject out of each photo and saves it: PNG with true alpha for a transparent background, otherwise JPEG on the chosen background.
    func runCutout(_ photos: [(name: String, data: Data)], background: CutoutConfig.Background, masker: SubjectMasking?) async {
        let list = Array(photos.prefix(Self.maxCutoutPhotos))
        items = list.map { Item(name: $0.name) }
        completed = 0; cancelled = false; isRunning = true
        defer { isRunning = false }
        for (i, photo) in list.enumerated() {
            if cancelled || Task.isCancelled { for j in i..<items.count { items[j].status = .failed("Cancelled") }; break }
            items[i].status = .working
            do {
                let out = try Self.cutOut(photo.data, background: background, masker: masker)
                try await saver.save(out)
                items[i].status = .done
            } catch { items[i].status = .failed(String(describing: error)) }
            completed += 1
        }
    }

    enum CutoutError: Error { case noSubject }

    nonisolated static func cutOut(_ data: Data, background: CutoutConfig.Background, masker: SubjectMasking?) throws -> Data {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw EditorError.undecodable }
        guard let masker, let mask = try masker.subjectMask(for: img) else { throw CutoutError.noSubject }
        var c = CutoutConfig(); c.background = background; c.feather = 0.1
        let out = CutoutOps.apply(c, to: img, subjectMask: mask)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw EditorError.exportFailed }
        let ctx = CIContext()
        let encoded = background == .transparent ? ctx.pngRepresentation(of: out, format: .RGBA8, colorSpace: space) : ctx.jpegRepresentation(of: out, colorSpace: space)
        guard let encoded else { throw EditorError.exportFailed }
        return encoded
    }

    nonisolated static func render(_ data: Data, recipe: Recipe, categories: Set<RecipeCategory>?) throws -> Data {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw EditorError.undecodable }
        let doc = recipe.apply(to: EditDocument(), categories: categories)
        let out = Renderer.render(img, document: doc)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let jpeg = CIContext().jpegRepresentation(of: out, colorSpace: space) else { throw EditorError.exportFailed }
        return jpeg
    }

}
