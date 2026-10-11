import Foundation

/// One non-destructive step. New tools add cases here; pixels are never baked until export.
enum EditOperation: Codable, Equatable {
    case exposure(Double)
    case crop(CropSpec)
    case adjust(AdjustParams)
    case curve(ToneCurve)
    case warp(WarpEdit)
    case layers(LayerStack)
    case remove([MaskCanvas])
    case cutout(CutoutConfig)
}

extension EditOperation {
    enum Kind: String, Codable, CaseIterable { case exposure, crop, adjust, curve, warp, layers, remove, cutout }
    var kind: Kind {
        switch self {
        case .exposure: .exposure
        case .crop: .crop
        case .adjust: .adjust
        case .curve: .curve
        case .warp: .warp
        case .layers: .layers
        case .remove: .remove
        case .cutout: .cutout
        }
    }
    /// Recipe category: what part of the look this belongs to.
    var category: RecipeCategory {
        switch self {
        case .crop: .geometry
        case .exposure, .adjust, .curve: .color
        case .warp: .beauty
        case .layers: .filter
        case .remove: .geometry
        case .cutout: .filter
        }
    }
}

enum RecipeCategory: String, Codable, CaseIterable { case color, geometry, beauty, body, filter, collage }
