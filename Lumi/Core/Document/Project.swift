import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var originalFileName: String
    var documentJSON: Data
    var thumbnail: Data?

    init(id: UUID = UUID(), originalFileName: String, document: EditDocument = EditDocument(), now: Date = .now) throws {
        self.id = id
        createdAt = now; updatedAt = now
        self.originalFileName = originalFileName
        documentJSON = try JSONEncoder().encode(document)
    }

    var document: EditDocument {
        (try? JSONDecoder().decode(EditDocument.self, from: documentJSON)) ?? EditDocument()
    }
}
