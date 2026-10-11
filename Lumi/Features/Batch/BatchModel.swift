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
    private let saver: PhotoSaving

    init(saver: PhotoSaving = LibraryPhotoSaver()) { self.saver = saver }

    var progress: Double { items.isEmpty ? 0 : Double(completed) / Double(items.count) }
    var failures: [Item] { items.filter { if case .failed = $0.status { true } else { false } } }

    /// `photos`: encoded image data with a display name each.
    func run(_ photos: [(name: String, data: Data)], recipe: Recipe, categories: Set<RecipeCategory>? = nil) async {
        items = photos.map { Item(name: $0.name) }
        completed = 0; isRunning = true
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

    nonisolated static func render(_ data: Data, recipe: Recipe, categories: Set<RecipeCategory>?) throws -> Data {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { throw EditorError.undecodable }
        let doc = recipe.apply(to: EditDocument(), categories: categories)
        let out = Renderer.render(img, document: doc)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let jpeg = CIContext().jpegRepresentation(of: out, colorSpace: space) else { throw EditorError.exportFailed }
        return jpeg
    }

}
