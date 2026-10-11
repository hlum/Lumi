import Foundation

struct EditDocument: Codable, Equatable {
    var operations: [EditOperation] = []

    var exposure: Double {
        get { operations.lazy.compactMap { if case .exposure(let v) = $0 { v } else { nil } }.last ?? 0 }
        set {
            operations.removeAll { if case .exposure = $0 { true } else { false } }
            if newValue != 0 { operations.append(.exposure(newValue)) }
        }
    }
}
