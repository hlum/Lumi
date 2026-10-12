import Foundation

struct CreditEntry: Codable, Equatable {
    var files: [String]
    var title: String
    var author: String
    var sourceURL: String
    var license: String
    var licenseURL: String
    var attribution: String
    var modified: Bool
    var modifiedNote: String?
    var dateAdded: String
    var selfMade: Bool
}

enum Credits {
    static let allowedLicenses: Set<String> = [
        "Self-made", "CC0", "CC-BY", "OFL", "MIT", "BSD", "Apache-2.0", "CC-BY-SA", "CC-BY-ND",
    ]
    /// Lumi is a personal app that is never released, so research and non-commercial licences are fine too. Still credited in full.
    static let personalUseLicenses: Set<String> = ["CC-BY-NC", "CC-BY-NC-SA", "CC-BY-NC-ND", "CreativeML-OpenRAIL-M", "Research-only", "GPL-3.0"]
    /// Allowed only if the asset is unmodified.
    static let unmodifiedOnly: Set<String> = ["CC-BY-SA", "CC-BY-ND"]

    static func decode(_ data: Data) throws -> [CreditEntry] {
        try JSONDecoder().decode([CreditEntry].self, from: data)
    }

    /// Returns human-readable problems; empty means valid.
    static func problems(in entries: [CreditEntry]) -> [String] {
        entries.enumerated().flatMap { i, e -> [String] in
            var p: [String] = []
            let name = e.title.isEmpty ? "entry \(i)" : e.title
            if e.files.isEmpty { p.append("\(name): no files") }
            for (field, v) in [("title", e.title), ("author", e.author), ("license", e.license), ("attribution", e.attribution), ("dateAdded", e.dateAdded)] where v.trimmingCharacters(in: .whitespaces).isEmpty {
                p.append("\(name): missing \(field)")
            }
            if !e.selfMade {
                if URL(string: e.sourceURL)?.scheme == nil { p.append("\(name): bad sourceURL") }
                if URL(string: e.licenseURL)?.scheme == nil { p.append("\(name): bad licenseURL") }
            }
            if !allowedLicenses.contains(e.license), !personalUseLicenses.contains(e.license) { p.append("\(name): license '\(e.license)' not allowed") }
            if unmodifiedOnly.contains(e.license), e.modified { p.append("\(name): \(e.license) must be unmodified") }
            if e.modified, (e.modifiedNote ?? "").isEmpty { p.append("\(name): modified without note") }
            if e.selfMade != (e.license == "Self-made") { p.append("\(name): selfMade and license disagree") }
            return p
        }
    }

    /// Files present but not named by any entry.
    static func uncovered(files: [String], entries: [CreditEntry]) -> [String] {
        let covered = Set(entries.flatMap(\.files))
        return files.filter { !covered.contains($0) }.sorted()
    }
}
