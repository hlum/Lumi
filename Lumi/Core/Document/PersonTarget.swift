import CoreGraphics
import Foundation

/// A detected person within one image. `name` is user-editable (portrait manager).
struct PersonTarget: Codable, Equatable, Identifiable {
    let id: Int
    var name: String
    var faceBox: CGRect
}

struct PersonSelection: Equatable {
    private(set) var people: [PersonTarget]
    private(set) var selected: Set<Int> = []

    init(faces: [FaceInfo]) {
        // left-to-right so numbering is stable and predictable
        people = faces.sorted { $0.box.minX < $1.box.minX }.enumerated().map {
            PersonTarget(id: $0.offset, name: "Person \($0.offset + 1)", faceBox: $0.element.box)
        }
    }

    var selectedPeople: [PersonTarget] { people.filter { selected.contains($0.id) } }

    mutating func toggle(_ id: Int) {
        guard people.contains(where: { $0.id == id }) else { return }
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Tap in normalized Vision space; selects the person whose face box contains it, if any.
    mutating func tap(_ p: CGPoint) {
        if let hit = people.first(where: { $0.faceBox.contains(p) }) { toggle(hit.id) }
    }

    mutating func selectAll() { selected = Set(people.map(\.id)) }
    mutating func clear() { selected = [] }

    mutating func rename(_ id: Int, to name: String) {
        guard let i = people.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        people[i].name = name
    }
}
