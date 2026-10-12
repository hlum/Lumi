import Foundation

/// Scrolls a script at a steady words-per-minute pace while the user records a voice-over.
struct Teleprompter: Equatable {
    var words: [String]
    var wordsPerMinute = 140.0

    init(script: String, wordsPerMinute: Double = 140) {
        words = script.split { $0.isWhitespace }.map(String.init)
        self.wordsPerMinute = wordsPerMinute
    }

    var duration: Double { wordsPerMinute > 0 ? Double(words.count) / wordsPerMinute * 60 : 0 }

    /// Index of the word being read at `t` seconds, clamped to the script.
    func currentWord(at t: Double) -> Int {
        guard !words.isEmpty, wordsPerMinute > 0 else { return 0 }
        return min(max(Int(t * wordsPerMinute / 60), 0), words.count - 1)
    }

    /// 0...1 progress through the script.
    func progress(at t: Double) -> Double { duration > 0 ? min(max(t / duration, 0), 1) : 0 }

    /// Words around the current one for a short on-screen window: what was read, what is being read, what is next.
    func window(at t: Double, before: Int = 6, after: Int = 14) -> (read: [String], current: String?, next: [String]) {
        guard !words.isEmpty else { return ([], nil, []) }
        let i = currentWord(at: t)
        return (Array(words[max(0, i - before)..<i]), words[i], Array(words[min(i + 1, words.count)..<min(i + 1 + after, words.count)]))
    }
}
