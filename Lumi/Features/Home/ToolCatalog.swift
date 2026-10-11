import Foundation

struct ToolInfo: Identifiable, Equatable {
    enum Category: String, CaseIterable { case edit, retouch, creative, utility }
    let id: String
    let name: String
    let symbol: String
    let category: Category
    let keywords: [String]
}

enum ToolCatalog {
    /// Tools that exist in the editor today. New tools register here.
    static let all: [ToolInfo] = [
        ToolInfo(id: "adjust", name: "Adjust", symbol: "slider.horizontal.3", category: .edit, keywords: ["brightness", "contrast", "saturation", "exposure", "warm", "cool", "明るさ", "色"]),
        ToolInfo(id: "crop", name: "Crop", symbol: "crop.rotate", category: .edit, keywords: ["rotate", "flip", "straighten", "ratio", "トリミング", "回転"]),
        ToolInfo(id: "text", name: "Text", symbol: "textformat", category: .creative, keywords: ["caption", "font", "words", "文字"]),
        ToolInfo(id: "remove", name: "Remove", symbol: "eraser", category: .edit, keywords: ["erase", "object", "clean", "inpaint", "消しゴム"]),
        ToolInfo(id: "cutout", name: "Cutout", symbol: "person.crop.rectangle", category: .edit, keywords: ["background", "subject", "transparent", "切り抜き", "背景"]),
        ToolInfo(id: "id-photo", name: "ID photo", symbol: "person.text.rectangle", category: .utility, keywords: ["passport", "visa", "証明写真"]),
        ToolInfo(id: "scanner", name: "Scanner", symbol: "doc.viewfinder", category: .utility, keywords: ["document", "pdf", "ocr", "スキャン"]),
        ToolInfo(id: "gif", name: "GIF maker", symbol: "film.stack", category: .utility, keywords: ["animation", "emoji", "sticker", "ジフ"]),
        ToolInfo(id: "collage", name: "Collage", symbol: "square.grid.2x2", category: .creative, keywords: ["grid", "layout", "stitch", "コラージュ"]),
    ]

    /// Matches name and keywords, case- and width-insensitive; names rank above keywords.
    static func search(_ query: String, in tools: [ToolInfo] = all) -> [ToolInfo] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: nil)
        guard !q.isEmpty else { return tools }
        func norm(_ s: String) -> String { s.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: nil) }
        let ranked: [(ToolInfo, Int)] = tools.compactMap { t in
            if norm(t.name).hasPrefix(q) { return (t, 0) }
            if norm(t.name).contains(q) { return (t, 1) }
            if t.keywords.contains(where: { norm($0).contains(q) }) { return (t, 2) }
            return nil
        }
        return ranked.sorted { $0.1 < $1.1 }.map(\.0)
    }

    static func grouped(_ tools: [ToolInfo] = all) -> [(ToolInfo.Category, [ToolInfo])] {
        ToolInfo.Category.allCases.compactMap { c in
            let t = tools.filter { $0.category == c }
            return t.isEmpty ? nil : (c, t)
        }
    }
}

/// Last-used tools, newest first, no duplicates, capped.
struct RecentTools: Codable, Equatable {
    private(set) var ids: [String] = []
    static let limit = 8
    mutating func used(_ id: String) {
        ids.removeAll { $0 == id }; ids.insert(id, at: 0)
        if ids.count > Self.limit { ids.removeLast(ids.count - Self.limit) }
    }
}
