import Foundation

struct TextPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let style: TextStyle
}

/// One-tap looks for text. Fonts are the bundled OFL ones or system fonts.
enum TextStylePresets {
    private static func style(_ font: String, size: Double = 0.07, color: RGBA = .white, stroke: Double = 0, strokeColor: RGBA = .black, shadow: Double = 0) -> TextStyle {
        var s = TextStyle(); s.fontName = font; s.size = size; s.color = color; s.strokeWidth = stroke; s.strokeColor = strokeColor; s.shadowRadius = shadow
        return s
    }

    static let all: [TextPreset] = [
        TextPreset(id: "clean", name: "Clean", style: style("HelveticaNeue-Bold", shadow: 0.1)),
        TextPreset(id: "outline", name: "Outline", style: style("HelveticaNeue-Bold", color: .white, stroke: 0.08, strokeColor: .black)),
        TextPreset(id: "poster", name: "Poster", style: style("BebasNeue-Regular", size: 0.12, color: .white, stroke: 0.02, shadow: 0.05)),
        TextPreset(id: "script", name: "Script", style: style("Pacifico-Regular", size: 0.09, color: RGBA(r: 1, g: 0.85, b: 0.9, a: 1), shadow: 0.12)),
        TextPreset(id: "handwritten", name: "Handwritten", style: style("Caveat-Regular", size: 0.1, color: RGBA(r: 1, g: 1, b: 0.85, a: 1), shadow: 0.08)),
        TextPreset(id: "pop", name: "Pop", style: style("DelaGothicOne-Regular", size: 0.09, color: RGBA(r: 1, g: 0.85, b: 0.2, a: 1), stroke: 0.06, strokeColor: RGBA(r: 0.9, g: 0.2, b: 0.3, a: 1))),
        TextPreset(id: "neon", name: "Neon", style: style("HelveticaNeue-Bold", color: RGBA(r: 0.6, g: 1, b: 0.95, a: 1), stroke: 0.01, strokeColor: RGBA(r: 0.2, g: 0.9, b: 1, a: 1), shadow: 0.5)),
        TextPreset(id: "retro", name: "Retro", style: style("RampartOne-Regular", size: 0.09, color: RGBA(r: 1, g: 0.55, b: 0.3, a: 1), stroke: 0.04, strokeColor: RGBA(r: 0.2, g: 0.1, b: 0.3, a: 1))),
        TextPreset(id: "maru", name: "Round", style: style("ZenMaruGothic-Bold", size: 0.08, color: RGBA(r: 0.35, g: 0.25, b: 0.45, a: 1), stroke: 0.1, strokeColor: .white)),
        TextPreset(id: "mono", name: "Typewriter", style: style("Menlo-Regular", size: 0.05, color: RGBA(r: 0.95, g: 0.95, b: 0.9, a: 1), shadow: 0.05)),
    ]

    static func preset(_ id: String) -> TextPreset? { all.first { $0.id == id } }

    /// Keeps the layer's text and placement; takes only the look.
    static func apply(_ p: TextPreset, to layer: Layer) -> Layer {
        guard case .text(let s, _) = layer.content else { return layer }
        var out = layer; out.content = .text(s, p.style); return out
    }
}
