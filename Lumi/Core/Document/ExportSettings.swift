import Foundation

enum LengthUnit: String, Codable, CaseIterable { case px, mm, cm, inch }

enum ImageFormat: String, Codable, CaseIterable {
    case heic, jpeg, png
    var supportsAlpha: Bool { self != .jpeg }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
}

struct ExportSettings: Codable, Equatable {
    var format: ImageFormat = .jpeg
    var quality = 0.9              // 0...1, ignored for PNG
    var maxLongSide: Int?          // nil = no limit

    static func pixels(_ value: Double, unit: LengthUnit, dpi: Double) -> Int {
        let inches: Double
        switch unit {
        case .px: return Int(value.rounded())
        case .inch: inches = value
        case .cm: inches = value / 2.54
        case .mm: inches = value / 25.4
        }
        return Int((inches * dpi).rounded())
    }

    /// Fit `size` inside `maxLongSide`, keeping aspect; never upscales; each side at least 1.
    func fitted(_ size: (w: Int, h: Int)) -> (w: Int, h: Int) {
        guard let m = maxLongSide, m > 0, max(size.w, size.h) > m else { return size }
        let s = Double(m) / Double(max(size.w, size.h))
        return (max(1, Int((Double(size.w) * s).rounded())), max(1, Int((Double(size.h) * s).rounded())))
    }

    /// Rough output size in bytes: a planning estimate only.
    func estimatedBytes(width: Int, height: Int) -> Int {
        let px = Double(width * height)
        switch format {
        case .png: return Int(px * 2.2)
        case .jpeg: return Int(px * (0.15 + 0.9 * quality * quality))
        case .heic: return Int(px * (0.08 + 0.45 * quality * quality))
        }
    }
}
