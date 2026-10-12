import Foundation

/// Works on mono samples; times are seconds.
enum SilenceDetector {
    /// Loudness (RMS) per window of `window` seconds.
    static func levels(_ samples: [Float], sampleRate: Double, window: Double = 0.02) -> [Float] {
        let n = max(Int(sampleRate * window), 1)
        return stride(from: 0, to: samples.count, by: n).map { i in
            let s = samples[i..<min(i + n, samples.count)]
            return (s.reduce(0) { $0 + $1 * $1 } / Float(s.count)).squareRoot()
        }
    }

    /// Stretches quieter than `threshold` (RMS 0...1) that last at least `minLength` seconds.
    static func silentRanges(_ samples: [Float], sampleRate: Double, threshold: Float = 0.01, minLength: Double = 0.5, window: Double = 0.02) -> [Range<Double>] {
        let lv = levels(samples, sampleRate: sampleRate, window: window)
        var out: [Range<Double>] = [], start: Int?
        func close(_ end: Int) {
            if let s = start, Double(end - s) * window >= minLength { out.append(Double(s) * window..<Double(end) * window) }
            start = nil
        }
        for (i, l) in lv.enumerated() { if l < threshold { if start == nil { start = i } } else { close(i) } }
        close(lv.count)
        return out
    }

    /// What is left after cutting the silences, leaving `padding` seconds of room at each cut so speech isn't clipped.
    static func keepRanges(duration: Double, silent: [Range<Double>], padding: Double = 0.1) -> [Range<Double>] {
        var keep: [Range<Double>] = [], cursor = 0.0
        for s in silent {
            let a = s.lowerBound + padding, b = s.upperBound - padding
            guard b > a else { continue }
            if a > cursor { keep.append(cursor..<a) }
            cursor = max(cursor, b)
        }
        if cursor < duration { keep.append(cursor..<duration) }
        return keep
    }

    /// Beat markers: moments where loudness jumps well above the recent average, at least `minGap` seconds apart.
    static func beats(_ samples: [Float], sampleRate: Double, sensitivity: Float = 1.6, minGap: Double = 0.25, window: Double = 0.02) -> [Double] {
        let lv = levels(samples, sampleRate: sampleRate, window: window)
        let lookback = max(Int(0.5 / window), 1)
        var out: [Double] = []
        for i in 1..<max(lv.count, 1) {
            let recent = lv[max(0, i - lookback)..<i], avg = recent.reduce(0, +) / Float(recent.count)
            let t = Double(i) * window
            if lv[i] > 0.02, lv[i] > avg * sensitivity, lv[i] >= lv[i - 1], (out.last.map { t - $0 >= minGap } ?? true) { out.append(t) }
        }
        return out
    }
}
