import CoreGraphics
import Foundation

/// One control point: the picture at `from` should end up at `to`. Image-normalized, y-down.
/// A pin is a handle whose `from` equals its `to`.
struct WarpHandle: Equatable {
    var from: CGPoint
    var to: CGPoint
    static func pin(_ p: CGPoint) -> WarpHandle { WarpHandle(from: p, to: p) }
}

/// Rigid moving-least-squares image deformation (Schaefer, McPhail and Warren, 2006), solved on a grid, weights 1/d⁴.
/// Shapes between handles move as rigidly as the handles allow: no bulges, no swirls. Pinned handles hold the rest still.
enum MLSWarp {
    /// The field for `handles`. `aspect` is image width / height (distances are measured in pixels, not normalized units).
    /// The field is a backward map: each output point samples the source at point + offset, as `MeshWarpRenderer` expects.
    static func field(_ handles: [WarpHandle], aspect: Double, cols: Int = 65, rows: Int? = nil) -> DisplacementField {
        let rows = rows ?? max(Int((Double(cols) / max(aspect, 0.1)).rounded()), 9)
        var f = DisplacementField(cols: cols, rows: rows)
        guard handles.contains(where: { $0.from != $0.to }) else { return f }
        let a = aspect
        // backward map: solve from the target positions to the source positions
        let p = handles.map { (x: Double($0.to.x) * a, y: Double($0.to.y)) }
        let q = handles.map { (x: Double($0.from.x) * a, y: Double($0.from.y)) }
        var w = [Double](repeating: 0, count: handles.count)
        // only the area the moves can reach needs solving: the box around every handle that isn't on the picture's edge, grown a little
        let inner = handles.filter { $0.to.x > 0.001 && $0.to.x < 0.999 && $0.to.y > 0.001 && $0.to.y < 0.999 }.map(\.to)
        let x0 = (inner.map(\.x).min() ?? 0) - 0.03, x1 = (inner.map(\.x).max() ?? 1) + 0.03
        let y0 = (inner.map(\.y).min() ?? 0) - 0.03, y1 = (inner.map(\.y).max() ?? 1) + 0.03
        let i0 = max(Int((Double(x0) * Double(cols - 1)).rounded(.down)), 0), i1 = min(Int((Double(x1) * Double(cols - 1)).rounded(.up)), cols - 1)
        let j0 = max(Int((Double(y0) * Double(rows - 1)).rounded(.down)), 0), j1 = min(Int((Double(y1) * Double(rows - 1)).rounded(.up)), rows - 1)
        guard i0 <= i1, j0 <= j1 else { return f }
        for j in j0...j1 {
            for i in i0...i1 {
                let vx = Double(i) / Double(cols - 1) * a, vy = Double(j) / Double(rows - 1)
                var src: (x: Double, y: Double)?
                var sw = 0.0
                for k in p.indices {
                    let d2 = (p[k].x - vx) * (p[k].x - vx) + (p[k].y - vy) * (p[k].y - vy)
                    if d2 < 1e-12 { src = q[k]; break }
                    w[k] = 1 / (d2 * d2); sw += w[k]     // 1/d^4: local, so pins hold firmly
                }
                if src == nil {
                    var px = 0.0, py = 0.0, qx = 0.0, qy = 0.0
                    for k in p.indices { px += w[k] * p[k].x; py += w[k] * p[k].y; qx += w[k] * q[k].x; qy += w[k] * q[k].y }
                    px /= sw; py /= sw; qx /= sw; qy /= sw
                    // rotation that best maps the p-hats to the q-hats around this point (complex: sum of w q̂ conj(p̂))
                    var re = 0.0, im = 0.0
                    for k in p.indices {
                        let ax = p[k].x - px, ay = p[k].y - py, bx = q[k].x - qx, by = q[k].y - qy
                        re += w[k] * (bx * ax + by * ay); im += w[k] * (by * ax - bx * ay)
                    }
                    let ux = vx - px, uy = vy - py, len = (ux * ux + uy * uy).squareRoot()
                    let rx = re * ux - im * uy, ry = re * uy + im * ux, rl = (rx * rx + ry * ry).squareRoot()
                    src = rl > 1e-12 ? (x: qx + len * rx / rl, y: qy + len * ry / rl) : (x: qx, y: qy)
                }
                let k = j * cols + i
                f.dx[k] = Float((src!.x - vx) / a)
                f.dy[k] = Float(src!.y - vy)
            }
        }
        return f
    }

    /// Pins on a ellipse (round in pixels) around `center`: everything outside stays where it is.
    static func ring(around center: CGPoint, radius: Double, aspect: Double, count: Int = 20) -> [WarpHandle] {
        (0..<count).map { i in
            let t = Double(i) / Double(count) * 2 * .pi
            return .pin(CGPoint(x: Double(center.x) + cos(t) * radius / aspect, y: Double(center.y) + sin(t) * radius))
        }
    }

    /// Pins along the picture's edges, so the frame never moves.
    static func border(perSide: Int = 6) -> [WarpHandle] {
        (0...perSide).flatMap { i -> [WarpHandle] in
            let t = Double(i) / Double(perSide)
            return [.pin(CGPoint(x: t, y: 0)), .pin(CGPoint(x: t, y: 1)), .pin(CGPoint(x: 0, y: t)), .pin(CGPoint(x: 1, y: t))]
        }
    }
}

extension DisplacementField {
    /// Two edits applied together. Exact composition when they don't overlap, close enough when the moves are small.
    func adding(_ other: DisplacementField) -> DisplacementField {
        guard cols == other.cols, rows == other.rows else {
            var out = self
            for j in 0..<rows { for i in 0..<cols {
                let (ox, oy) = other.offset(x: Float(i) / Float(cols - 1), y: Float(j) / Float(rows - 1))
                out.dx[j * cols + i] += ox; out.dy[j * cols + i] += oy
            } }
            return out
        }
        var out = self
        for k in dx.indices { out.dx[k] += other.dx[k]; out.dy[k] += other.dy[k] }
        return out
    }
}
