import Foundation

/// One non-destructive step. New tools add cases here; pixels are never baked until export.
enum EditOperation: Codable, Equatable {
    case exposure(Double)
}
