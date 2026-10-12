import Foundation

/// A value over time. Keys are kept sorted; between keys the value eases, outside them it holds.
struct Track: Codable, Equatable {
    enum Ease: String, Codable { case linear, easeIn, easeOut, easeInOut, hold }
    struct Key: Codable, Equatable { var time: Double; var value: Double; var ease = Ease.linear }
    private(set) var keys: [Key] = []

    mutating func set(_ value: Double, at time: Double, ease: Ease = .linear) {
        if let i = keys.firstIndex(where: { abs($0.time - time) < 1e-6 }) { keys[i].value = value; keys[i].ease = ease }
        else { keys.append(Key(time: time, value: value, ease: ease)); keys.sort { $0.time < $1.time } }
    }
    mutating func remove(at time: Double) { keys.removeAll { abs($0.time - time) < 1e-6 } }

    func value(at t: Double, default d: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return d }
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }
        let i = keys.lastIndex { $0.time <= t }!
        let a = keys[i], b = keys[i + 1]
        if a.ease == .hold { return a.value }
        let u = Self.curve(a.ease, (t - a.time) / (b.time - a.time))
        return a.value + (b.value - a.value) * u
    }

    static func curve(_ e: Ease, _ u: Double) -> Double {
        switch e {
        case .linear, .hold: u
        case .easeIn: u * u
        case .easeOut: 1 - (1 - u) * (1 - u)
        case .easeInOut: u < 0.5 ? 2 * u * u : 1 - 2 * (1 - u) * (1 - u)
        }
    }
}

/// Position, scale, rotation and opacity over time.
struct Keyframes: Codable, Equatable {
    var x = Track(), y = Track(), scale = Track(), rotation = Track(), opacity = Track()

    struct Pose: Equatable { var x: Double, y: Double, scale: Double, rotation: Double, opacity: Double }
    func pose(at t: Double, base: Pose = Pose(x: 0.5, y: 0.5, scale: 1, rotation: 0, opacity: 1)) -> Pose {
        Pose(x: x.value(at: t, default: base.x), y: y.value(at: t, default: base.y), scale: scale.value(at: t, default: base.scale),
             rotation: rotation.value(at: t, default: base.rotation), opacity: min(max(opacity.value(at: t, default: base.opacity), 0), 1))
    }
}
