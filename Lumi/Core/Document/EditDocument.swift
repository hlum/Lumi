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

    private mutating func set(_ op: EditOperation?, replacing match: (EditOperation) -> Bool) {
        operations.removeAll(where: match)
        if let op { operations.append(op) }
    }

    var crop: CropSpec {
        get { operations.lazy.compactMap { if case .crop(let v) = $0 { v } else { nil } }.last ?? CropSpec() }
        set { set(newValue.isIdentity ? nil : .crop(newValue)) { if case .crop = $0 { true } else { false } } }
    }
    var adjust: AdjustParams {
        get { operations.lazy.compactMap { if case .adjust(let v) = $0 { v } else { nil } }.last ?? AdjustParams() }
        set { set(newValue.isIdentity ? nil : .adjust(newValue)) { if case .adjust = $0 { true } else { false } } }
    }
    var curve: ToneCurve {
        get { operations.lazy.compactMap { if case .curve(let v) = $0 { v } else { nil } }.last ?? ToneCurve() }
        set { set(newValue.isIdentity ? nil : .curve(newValue)) { if case .curve = $0 { true } else { false } } }
    }

    var warp: WarpEdit {
        get { operations.lazy.compactMap { if case .warp(let v) = $0 { v } else { nil } }.last ?? WarpEdit() }
        set { set(newValue.strokes.isEmpty ? nil : .warp(newValue)) { if case .warp = $0 { true } else { false } } }
    }

    var layers: LayerStack {
        get { operations.lazy.compactMap { if case .layers(let v) = $0 { v } else { nil } }.last ?? LayerStack() }
        set { set(newValue.layers.isEmpty ? nil : .layers(newValue)) { if case .layers = $0 { true } else { false } } }
    }

    /// Remover masks, applied in order (each pass removes more).
    var removals: [MaskCanvas] {
        get { operations.lazy.compactMap { if case .remove(let v) = $0 { v } else { nil } }.last ?? [] }
        set { set(newValue.isEmpty ? nil : .remove(newValue)) { if case .remove = $0 { true } else { false } } }
    }

    var cutout: CutoutConfig? {
        get { operations.lazy.compactMap { if case .cutout(let v) = $0 { v } else { nil } }.last }
        set { set(newValue.map { .cutout($0) }) { if case .cutout = $0 { true } else { false } } }
    }

    var expand: ExpandConfig {
        get { operations.lazy.compactMap { if case .expand(let v) = $0 { v } else { nil } }.last ?? ExpandConfig() }
        set { set(newValue.isIdentity ? nil : .expand(newValue)) { if case .expand = $0 { true } else { false } } }
    }

    /// The applied filter (id and 0...1 intensity), or nil.
    var filter: (id: String, intensity: Double)? {
        get { operations.lazy.compactMap { if case .filter(let id, let i) = $0 { (id, i) } else { nil } }.last }
        set { set(newValue.map { .filter(id: $0.id, intensity: min(max($0.intensity, 0), 1)) }) { if case .filter = $0 { true } else { false } } }
    }

    var frame: FrameConfig {
        get { operations.lazy.compactMap { if case .frame(let v) = $0 { v } else { nil } }.last ?? FrameConfig() }
        set { set(newValue.isIdentity ? nil : .frame(newValue)) { if case .frame = $0 { true } else { false } } }
    }
    var doodle: [DoodleStroke] {
        get { operations.lazy.compactMap { if case .doodle(let v) = $0 { v } else { nil } }.last ?? [] }
        set { set(newValue.isEmpty ? nil : .doodle(newValue)) { if case .doodle = $0 { true } else { false } } }
    }

    var mosaic: MosaicConfig {
        get { operations.lazy.compactMap { if case .mosaic(let v) = $0 { v } else { nil } }.last ?? MosaicConfig() }
        set { set(newValue.isIdentity ? nil : .mosaic(newValue)) { if case .mosaic = $0 { true } else { false } } }
    }
    var watermark: Watermark? {
        get { operations.lazy.compactMap { if case .watermark(let v) = $0 { v } else { nil } }.last }
        set { set(newValue.map { .watermark($0) }) { if case .watermark = $0 { true } else { false } } }
    }

    /// 2 or 4 (times the pixel size), or nil.
    var upscale: Int? {
        get { operations.lazy.compactMap { if case .upscale(let f) = $0 { f } else { nil } }.last }
        set { set(newValue.flatMap { [2, 4].contains($0) ? EditOperation.upscale(factor: $0) : nil }) { if case .upscale = $0 { true } else { false } } }
    }

    /// Colorize a black-and-white photo; strength 0...1 blends from the original.
    var colorize: Double? {
        get { operations.lazy.compactMap { if case .colorize(let v) = $0 { v } else { nil } }.last }
        set { set(newValue.map { .colorize(strength: min(max($0, 0), 1)) }) { if case .colorize = $0 { true } else { false } } }
    }

    var grade: ColorGrade {
        get { operations.lazy.compactMap { if case .grade(let v) = $0 { v } else { nil } }.last ?? ColorGrade() }
        set { set(newValue.isIdentity ? nil : .grade(newValue)) { if case .grade = $0 { true } else { false } } }
    }

    /// Applies operations (e.g. from a recipe): each replaces any existing operation of the same kind.
    func applying(_ ops: [EditOperation]) -> EditDocument {
        var d = self
        for op in ops {
            d.operations.removeAll { $0.kind == op.kind }
            d.operations.append(op)
        }
        return d
    }
}
