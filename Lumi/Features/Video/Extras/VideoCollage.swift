import CoreImage
import Foundation

/// Several clips playing at once in a collage layout. The result is capped at `maxDuration`.
struct VideoCollage: Equatable {
    static let maxDuration = 20.0
    var layout: CollageLayout
    var clipDurations: [Double]      // one per slot, in order
    var loopShort = true             // shorter clips loop; otherwise they hold their last frame

    /// Length of the output: the longest clip, never over the cap.
    var duration: Double { min(clipDurations.max() ?? 0, Self.maxDuration) }

    /// Which time inside clip `i` to show at output time `t`.
    func sourceTime(slot i: Int, at t: Double) -> Double? {
        guard clipDurations.indices.contains(i), clipDurations[i] > 0, t >= 0, t < duration else { return nil }
        let d = clipDurations[i]
        if t < d { return t }
        return loopShort ? t.truncatingRemainder(dividingBy: d) : max(d - 0.001, 0)
    }

    /// One output frame: the slots' frames at time `t`, laid out with the still-collage renderer.
    func frame(at t: Double, frames: [CIImage], width: Int) -> CIImage? {
        guard !frames.isEmpty, t >= 0, t < duration else { return nil }
        var state = CollageState(layout: layout, photoCount: frames.count)
        for i in state.fills.indices { state.fills[i].photo = i }
        return CollageRenderer.render(state, photos: frames, width: width)
    }
}
