import CoreGraphics
import Foundation

struct RGBA: Codable, Equatable {
    var r = 1.0, g = 1.0, b = 1.0, a = 1.0
    static let white = RGBA(), black = RGBA(r: 0, g: 0, b: 0, a: 1)
}

/// Placement in normalized image space so preview and full-res export lay out identically.
struct LayerTransform: Codable, Equatable {
    var center = CGPoint(x: 0.5, y: 0.5)   // 0...1, origin top-left
    var scale = 1.0
    var rotation = 0.0                      // radians, clockwise
    var flipH = false
}

struct TextStyle: Codable, Equatable {
    var fontName = "HelveticaNeue-Bold"
    var size = 0.06                         // fraction of image height
    var color = RGBA.white
    var strokeWidth = 0.0                   // fraction of font size
    var strokeColor = RGBA.black
    var shadowRadius = 0.0                  // fraction of font size
    var alignment = Alignment.center
    enum Alignment: String, Codable { case left, center, right }
}

struct Layer: Codable, Equatable, Identifiable {
    enum Content: Codable, Equatable {
        case text(String, TextStyle)
        case sticker(id: String, outline: Double)   // outline width as fraction of sticker size, 0 = none
    }
    var id = UUID()
    var content: Content
    var transform = LayerTransform()
    var opacity = 1.0
    /// Draw the layer behind the main subject (the subject is put back on top).
    var behindSubject = false

    var isSticker: Bool { if case .sticker = content { true } else { false } }

    init(id: UUID = UUID(), content: Content, transform: LayerTransform = LayerTransform(), opacity: Double = 1, behindSubject: Bool = false) {
        self.id = id; self.content = content; self.transform = transform; self.opacity = opacity; self.behindSubject = behindSubject
    }

    // Drafts saved before a field existed must still open: every field after the first release is optional on decode.
    enum CodingKeys: String, CodingKey { case id, content, transform, opacity, behindSubject }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        content = try c.decode(Content.self, forKey: .content)
        transform = try c.decodeIfPresent(LayerTransform.self, forKey: .transform) ?? LayerTransform()
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        behindSubject = try c.decodeIfPresent(Bool.self, forKey: .behindSubject) ?? false
    }
}

/// Ordered overlay layers (back to front) with the product limits.
struct LayerStack: Codable, Equatable {
    static let maxStickers = 25
    private(set) var layers: [Layer] = []

    enum AddError: Error, Equatable { case stickerLimit, emptyText }

    mutating func add(_ layer: Layer) throws {
        if layer.isSticker, layers.filter(\.isSticker).count >= Self.maxStickers { throw AddError.stickerLimit }
        if case .text(let s, _) = layer.content, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw AddError.emptyText }
        layers.append(layer)
    }
    mutating func remove(_ id: UUID) { layers.removeAll { $0.id == id } }
    mutating func update(_ id: UUID, _ change: (inout Layer) -> Void) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        change(&layers[i])
        layers[i].opacity = min(max(layers[i].opacity, 0), 1)
        layers[i].transform.scale = min(max(layers[i].transform.scale, 0.05), 20)
    }
    mutating func bringToFront(_ id: UUID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        layers.append(layers.remove(at: i))
    }
    mutating func sendToBack(_ id: UUID) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        layers.insert(layers.remove(at: i), at: 0)
    }
}
