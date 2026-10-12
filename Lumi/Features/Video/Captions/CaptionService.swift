import Foundation

struct Caption: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
    var translation: String?          // second language line (Translation framework)
}

struct CaptionStyle: Codable, Equatable {
    var fontName = "System"
    var size = 0.05                   // fraction of frame height
    var color = RGBA.white
    var background = RGBA(r: 0, g: 0, b: 0, a: 0.5)
    var position = 0.85               // vertical center, frame-normalized y-down
    var bilingual = false
}

/// Speech-to-text source. The real one wraps the on-device `SpeechAnalyzer`; tests use a fake.
protocol Transcribing {
    func transcribe(audio: URL, locale: Locale) async throws -> [Caption]
}

struct CaptionTrack: Codable, Equatable {
    var captions: [Caption] = []
    var style = CaptionStyle()

    func caption(at t: Double) -> Caption? { captions.first { t >= $0.start && t < $0.end } }

    mutating func edit(_ id: UUID, text: String) {
        guard let i = captions.firstIndex(where: { $0.id == id }) else { return }
        captions[i].text = text
    }

    /// Splits a caption in two at time `t`, dividing the words in proportion.
    mutating func split(_ id: UUID, at t: Double) {
        guard let i = captions.firstIndex(where: { $0.id == id }), t > captions[i].start, t < captions[i].end else { return }
        let c = captions[i], words = c.text.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return }
        let cut = min(max(Int((Double(words.count) * (t - c.start) / (c.end - c.start)).rounded()), 1), words.count - 1)
        var a = c, b = c
        a.end = t; a.text = words[..<cut].joined(separator: " ")
        b.id = UUID(); b.start = t; b.text = words[cut...].joined(separator: " ")
        captions.replaceSubrange(i...i, with: [a, b])
    }

    mutating func merge(_ id: UUID) {
        guard let i = captions.firstIndex(where: { $0.id == id }), i + 1 < captions.count else { return }
        captions[i].end = captions[i + 1].end
        captions[i].text += " " + captions[i + 1].text
        captions.remove(at: i + 1)
    }

    mutating func shift(by dt: Double) { for i in captions.indices { captions[i].start = max(0, captions[i].start + dt); captions[i].end = max(0, captions[i].end + dt) } }

    /// Fills `translation` for every caption (the real translator is async; this applies its result).
    mutating func applyTranslations(_ lines: [String]) {
        for (i, l) in lines.enumerated() where captions.indices.contains(i) { captions[i].translation = l }
    }
}

enum SRT {
    static func timestamp(_ t: Double) -> String {
        let ms = Int((max(t, 0) * 1000).rounded()), h = ms / 3_600_000, m = ms / 60_000 % 60, s = ms / 1000 % 60
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms % 1000)
    }

    static func export(_ track: CaptionTrack) -> String {
        track.captions.enumerated().map { i, c in
            let text = track.style.bilingual ? [c.text, c.translation].compactMap { $0 }.joined(separator: "\n") : c.text
            return "\(i + 1)\n\(timestamp(c.start)) --> \(timestamp(c.end))\n\(text)\n"
        }.joined(separator: "\n")
    }

    static func seconds(_ s: String) -> Double? {
        let p = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard p.count == 3, let h = Double(p[0]), let m = Double(p[1]), let sec = Double(p[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }

    static func parse(_ text: String) -> [Caption] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n").compactMap { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let times = lines[ti].components(separatedBy: "-->")
            guard times.count == 2, let a = seconds(times[0]), let b = seconds(times[1]), b > a else { return nil }
            let body = lines[(ti + 1)...].joined(separator: "\n")
            return body.isEmpty ? nil : Caption(start: a, end: b, text: body)
        }
    }
}
