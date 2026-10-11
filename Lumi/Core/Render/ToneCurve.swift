import Foundation

/// Monotone cubic (Fritsch–Carlson) curve through control points in 0...1; never overshoots.
struct ToneCurve: Codable, Equatable {
    var points: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]

    static let presets: [String: ToneCurve] = [
        "contrast": ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.25, y: 0.18), CGPoint(x: 0.75, y: 0.82), CGPoint(x: 1, y: 1)]),
        "fade": ToneCurve(points: [CGPoint(x: 0, y: 0.08), CGPoint(x: 1, y: 0.95)]),
    ]

    var isIdentity: Bool { self == ToneCurve() }

    private var sorted: [CGPoint] {
        var out: [CGPoint] = []
        for p in points.sorted(by: { $0.x < $1.x }) where out.last.map({ $0.x < p.x }) ?? true {
            out.append(CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1)))
        }
        return out
    }

    func value(at x: Double) -> Double {
        let p = sorted
        guard p.count >= 2 else { return x }
        if x <= Double(p[0].x) { return Double(p[0].y) }
        if x >= Double(p[p.count - 1].x) { return Double(p[p.count - 1].y) }
        let n = p.count
        var d = [Double](repeating: 0, count: n - 1), m = [Double](repeating: 0, count: n)
        for i in 0..<n - 1 { d[i] = Double(p[i + 1].y - p[i].y) / Double(p[i + 1].x - p[i].x) }
        m[0] = d[0]; m[n - 1] = d[n - 2]
        for i in 1..<n - 1 { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
        for i in 0..<n - 1 where d[i] == 0 { m[i] = 0; m[i + 1] = 0 }
        for i in 0..<n - 1 where d[i] != 0 {
            let a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b
            if s > 9 { let t = 3 / s.squareRoot(); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
        }
        var i = 0
        while Double(p[i + 1].x) < x { i += 1 }
        let h = Double(p[i + 1].x - p[i].x), t = (x - Double(p[i].x)) / h
        let t2 = t * t, t3 = t2 * t
        let y = (2 * t3 - 3 * t2 + 1) * Double(p[i].y) + (t3 - 2 * t2 + t) * h * m[i]
              + (-2 * t3 + 3 * t2) * Double(p[i + 1].y) + (t3 - t2) * h * m[i + 1]
        return min(max(y, 0), 1)
    }

    /// 256-entry lookup table.
    var lut: [UInt8] { (0..<256).map { UInt8((value(at: Double($0) / 255) * 255).rounded()) } }
}
