import Foundation

/// CLIP's byte-pair tokenizer, as Stable Diffusion 1.x uses it: lower-cased words, merges by rank, 77 ids from start to end token, padded with the end token.
struct CLIPTokenizer {
    static let start = 49406, end = 49407, length = 77

    private let vocab: [String: Int]
    private let ranks: [String: Int]
    private let byteToUnicode: [UInt8: Character]
    private static let pattern = try! NSRegularExpression(pattern: #"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#)

    init(vocabURL: URL, mergesURL: URL) throws {
        vocab = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: vocabURL))
        let lines = try String(contentsOf: mergesURL, encoding: .utf8).split(separator: "\n").dropFirst()
        var r: [String: Int] = [:]
        for (i, l) in lines.enumerated() where i < 48894 { r[String(l)] = i }
        ranks = r
        // the standard GPT-2 byte table: printable bytes map to themselves, the rest to code points above 255
        var printable = Array(33...126) + Array(161...172) + Array(174...255)
        var table: [UInt8: Character] = [:]
        for b in printable { table[UInt8(b)] = Character(UnicodeScalar(b)!) }
        var extra = 0
        for b in 0...255 where !printable.contains(b) { table[UInt8(b)] = Character(UnicodeScalar(256 + extra)!); extra += 1 }
        printable.removeAll()
        byteToUnicode = table
    }

    /// Token ids for `text`: `[start] + tokens + [end]`, cut or padded to 77.
    func encode(_ text: String) -> [Int] {
        var ids = [Self.start]
        let s = text.lowercased()
        for m in Self.pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r = Range(m.range, in: s) else { continue }
            let word = String(s[r]).utf8.compactMap { byteToUnicode[$0] }
            for piece in bpe(word) { if let id = vocab[piece] { ids.append(id) } }
        }
        ids = Array(ids.prefix(Self.length - 1)) + [Self.end]
        return ids + Array(repeating: Self.end, count: Self.length - ids.count)
    }

    private func bpe(_ chars: [Character]) -> [String] {
        guard !chars.isEmpty else { return [] }
        var parts = chars.dropLast().map(String.init) + [String(chars.last!) + "</w>"]
        while parts.count > 1 {
            var best: (rank: Int, index: Int)?
            for i in 0..<(parts.count - 1) { if let r = ranks[parts[i] + " " + parts[i + 1]], best == nil || r < best!.rank { best = (r, i) } }
            guard let b = best else { break }
            parts.replaceSubrange(b.index...b.index + 1, with: [parts[b.index] + parts[b.index + 1]])
        }
        return parts
    }
}
