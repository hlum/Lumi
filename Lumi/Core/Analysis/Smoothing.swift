import Foundation

/// One-Euro filter (Casiez et al.): low lag when moving fast, low jitter when still.
struct OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double = 1
    private var x: Double?
    private var dx = 0.0
    private var t: Double?

    init(minCutoff: Double = 1, beta: Double = 0.01) { self.minCutoff = minCutoff; self.beta = beta }

    private static func alpha(_ cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let px = x, let pt = t, time > pt else { x = x ?? value; t = t ?? time; return x! }
        let dt = time - pt
        let rawD = (value - px) / dt
        dx += Self.alpha(dCutoff, dt: dt) * (rawD - dx)
        let cutoff = minCutoff + beta * abs(dx)
        let nx = px + Self.alpha(cutoff, dt: dt) * (value - px)
        x = nx; t = time
        return nx
    }

    mutating func reset() { x = nil; t = nil; dx = 0 }
}

/// Smooths a 2D point track (landmarks).
struct PointSmoother {
    private var fx: OneEuroFilter, fy: OneEuroFilter
    init(minCutoff: Double = 1, beta: Double = 0.01) {
        fx = OneEuroFilter(minCutoff: minCutoff, beta: beta); fy = fx
    }
    mutating func filter(_ p: CGPoint, at t: Double) -> CGPoint {
        CGPoint(x: fx.filter(p.x, at: t), y: fy.filter(p.y, at: t))
    }
}
