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
