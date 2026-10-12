import Foundation

/// One audio clip on the timeline: music, voice-over, sound effect or speech.
struct AudioClip: Codable, Equatable, Identifiable {
    enum Source: Codable, Equatable { case file(URL), voiceOver(URL), soundEffect(String), speech(URL), extracted(URL) }
    var id = UUID()
    var source: Source
    var start = 0.0              // where it begins on the timeline
    var trimIn = 0.0, trimOut: Double   // part of the source used; trimOut is the end
    var volume = 1.0             // 0...2
    var fadeIn = 0.0, fadeOut = 0.0
    var voiceEnhance = false     // EQ and dynamics preset

    init(source: Source, duration: Double, start: Double = 0) { self.source = source; trimOut = duration; self.start = start }

    var length: Double { max(trimOut - trimIn, 0) }
    var end: Double { start + length }

    /// Gain at timeline time `t` (0 outside the clip).
    func gain(at t: Double) -> Double {
        guard t >= start, t < end else { return 0 }
        let local = t - start
        var g = min(max(volume, 0), 2)
        if fadeIn > 0 { g *= min(local / fadeIn, 1) }
        if fadeOut > 0 { g *= min((length - local) / fadeOut, 1) }
        return g
    }

    mutating func setFades(in a: Double, out b: Double) {
        let total = min(max(a, 0) + max(b, 0), length)
        guard total > 0 else { fadeIn = 0; fadeOut = 0; return }
        let k = (max(a, 0) + max(b, 0)) > length ? length / (max(a, 0) + max(b, 0)) : 1     // both fades never overlap
        fadeIn = max(a, 0) * k; fadeOut = max(b, 0) * k
    }

    mutating func trim(in a: Double, out b: Double, sourceDuration: Double) {
        trimIn = min(max(a, 0), sourceDuration); trimOut = min(max(b, trimIn), sourceDuration)
        fadeIn = min(fadeIn, length); fadeOut = min(fadeOut, length - fadeIn)
    }

    /// Splits at timeline time `t` into two clips that play the same audio back to back.
    func split(at t: Double) -> (AudioClip, AudioClip)? {
        guard t > start, t < end else { return nil }
        var a = self, b = self
        b.id = UUID()
        a.trimOut = trimIn + (t - start); a.fadeOut = 0
        b.trimIn = a.trimOut; b.start = t; b.fadeIn = 0
        return (a, b)
    }
}

struct AudioTracks: Codable, Equatable {
    var clips: [AudioClip] = []
    var duration: Double { clips.map(\.end).max() ?? 0 }
    mutating func add(_ c: AudioClip) { clips.append(c) }
    mutating func remove(_ id: UUID) { clips.removeAll { $0.id == id } }
    /// Combined gain of everything playing at `t` (for the preview meter).
    func gain(at t: Double) -> Double { clips.reduce(0) { $0 + $1.gain(at: t) } }

    /// Lowers music while a voice-over or speech clip plays ("ducking").
    func duckedGain(of clip: AudioClip, at t: Double, duck: Double = 0.3) -> Double {
        let voiceOn = clips.contains { c in
            switch c.source { case .voiceOver, .speech: c.gain(at: t) > 0; default: false }
        }
        if case .file = clip.source, voiceOn { return clip.gain(at: t) * duck }
        return clip.gain(at: t)
    }
}
