import Foundation

/// Named masks belonging to one document.
struct MaskStore: Codable, Equatable {
    private(set) var masks: [String: MaskCanvas] = [:]
    subscript(id: String) -> MaskCanvas? {
        get { masks[id] }
        set { masks[id] = newValue }
    }
    mutating func remove(_ id: String) { masks[id] = nil }
}
