import Foundation

/// Source-offset field on a cols x rows grid, in normalized image units (0...1).
/// An output point p samples the source at p + offset(p). Codable so edits stay non-destructive.
struct DisplacementField: Codable, Equatable {
    let cols: Int
    let rows: Int
    private(set) var dx: [Float]
    private(set) var dy: [Float]

    init(cols: Int, rows: Int) {
        precondition(cols >= 2 && rows >= 2)
        self.cols = cols; self.rows = rows
        dx = Array(repeating: 0, count: cols * rows)
        dy = dx
    }

    var isIdentity: Bool { !dx.contains { $0 != 0 } && !dy.contains { $0 != 0 } }

    /// Bilinear sample at normalized (x, y); clamps outside 0...1 so edges never tear.
    func offset(x: Float, y: Float) -> (Float, Float) {
        let gx = min(max(x, 0), 1) * Float(cols - 1), gy = min(max(y, 0), 1) * Float(rows - 1)
        let x0 = min(Int(gx), cols - 2), y0 = min(Int(gy), rows - 2)
        let fx = gx - Float(x0), fy = gy - Float(y0)
        func lerp(_ a: [Float]) -> Float {
            let i = y0 * cols + x0
            let top = a[i] * (1 - fx) + a[i + 1] * fx
            let bot = a[i + cols] * (1 - fx) + a[i + cols + 1] * fx
            return top * (1 - fy) + bot * fy
        }
        return (lerp(dx), lerp(dy))
    }

    mutating func apply(_ s: BrushStroke) {
        guard s.radius > 0 else { return }
        for j in 0..<rows { for i in 0..<cols {
            let px = Float(i) / Float(cols - 1), py = Float(j) / Float(rows - 1)
            let vx = px - s.x, vy = py - s.y
            let d = (vx * vx + vy * vy).squareRoot() / s.radius
            guard d < 1 else { continue }
            let w = s.strength * (1 - d) * (1 - d) * (1 + 2 * d)  // smoothstep falloff
            let k = j * cols + i
            switch s.kind {
            case .push:   dx[k] -= s.dirX * w; dy[k] -= s.dirY * w
            case .pinch:  dx[k] += vx * w;     dy[k] += vy * w
            case .bloat:  dx[k] -= vx * w;     dy[k] -= vy * w
            }
        } }
    }
}

struct BrushStroke: Codable, Equatable {
    enum Kind: String, Codable { case pinch, bloat, push }
    var kind: Kind
    var x: Float, y: Float          // center, normalized
    var radius: Float               // normalized
    var strength: Float             // 0...1
    var dirX: Float = 0, dirY: Float = 0  // push drag vector, normalized
}

/// Strokes are the source of truth; the field is replayed from them, so undo is exact.
struct WarpEdit: Codable, Equatable {
    let cols: Int, rows: Int
    private(set) var strokes: [BrushStroke] = []
    private var undone: [BrushStroke] = []

    init(cols: Int = 33, rows: Int = 33) { self.cols = cols; self.rows = rows }

    var canUndo: Bool { !strokes.isEmpty }
    var canRedo: Bool { !undone.isEmpty }

    mutating func add(_ s: BrushStroke) { strokes.append(s); undone.removeAll() }
    mutating func undo() { if let s = strokes.popLast() { undone.append(s) } }
    mutating func redo() { if let s = undone.popLast() { strokes.append(s) } }

    var field: DisplacementField {
        var f = DisplacementField(cols: cols, rows: rows)
        strokes.forEach { f.apply($0) }
        return f
    }
}
