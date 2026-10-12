import CoreGraphics

/// Face detections frame by frame, smoothed so retouch doesn't shimmer. Faces are matched by nearest box center.
struct FrameAnalysisTrack {
    var smoothing = 0.6              // 0 = raw, toward 1 = heavy
    var cutDistance = 0.25           // a jump larger than this (fraction of the frame) is a new shot, not motion
    private(set) var last: [FaceInfo] = []

    mutating func update(_ detected: [FaceInfo]) -> [FaceInfo] {
        var out: [FaceInfo] = []
        var free = last
        for f in detected {
            guard let i = free.indices.min(by: { dist(free[$0].box, f.box) < dist(free[$1].box, f.box) }), dist(free[i].box, f.box) < cutDistance else { out.append(f); continue }
            out.append(blend(free.remove(at: i), f))
        }
        last = out
        return out
    }

    mutating func reset() { last = [] }

    private func dist(_ a: CGRect, _ b: CGRect) -> Double { Double(hypot(a.midX - b.midX, a.midY - b.midY)) }

    private func blend(_ old: FaceInfo, _ new: FaceInfo) -> FaceInfo {
        let k = CGFloat(min(max(smoothing, 0), 0.95))
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a * k + b * (1 - k) }
        var f = new
        f.box = CGRect(x: mix(old.box.minX, new.box.minX), y: mix(old.box.minY, new.box.minY), width: mix(old.box.width, new.box.width), height: mix(old.box.height, new.box.height))
        for (name, pts) in new.landmarks {
            guard let o = old.landmarks[name], o.count == pts.count else { continue }
            f.landmarks[name] = zip(o, pts).map { CGPoint(x: mix($0.x, $1.x), y: mix($0.y, $1.y)) }
        }
        return f
    }
}
