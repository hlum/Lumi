import Foundation
import Testing
@testable import Lumi

struct CreditsTests {
    static func entry(_ mutate: (inout CreditEntry) -> Void = { _ in }) -> CreditEntry {
        var e = CreditEntry(files: ["a.png"], title: "A", author: "Au", sourceURL: "https://x.test/a", license: "CC-BY",
                            licenseURL: "https://creativecommons.org/licenses/by/4.0/", attribution: "A by Au", modified: false,
                            modifiedNote: nil, dateAdded: "2026-10-11", selfMade: false)
        mutate(&e)
        return e
    }

    // MARK: shipped data
    @Test func shippedCreditsFileDecodesAndIsComplete() throws {
        let url = try #require(Bundle.main.url(forResource: "Credits", withExtension: "json"))
        let entries = try Credits.decode(Data(contentsOf: url))
        #expect(Credits.problems(in: entries).isEmpty)
    }

    @Test func everyShippedContentFileIsCredited() throws {
        let url = try #require(Bundle.main.url(forResource: "Credits", withExtension: "json"))
        let entries = try Credits.decode(Data(contentsOf: url))
        let root = Bundle.main.resourceURL!.appendingPathComponent("Content")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?.compactMap { $0 as? URL } ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && !$0.lastPathComponent.hasPrefix(".") }
            .map { String($0.path.dropFirst(root.path.count + 1)) }
        #expect(Credits.uncovered(files: files, entries: entries).isEmpty)
    }

    // MARK: validator
    @Test func validEntryPasses() { #expect(Credits.problems(in: [Self.entry()]).isEmpty) }

    @Test func emptyListPasses() { #expect(Credits.problems(in: []).isEmpty) }

    @Test(arguments: ["Unknown", "", "All rights reserved"])
    func disallowedLicenseFails(license: String) {
        #expect(!Credits.problems(in: [Self.entry { $0.license = license }]).isEmpty)
    }

    @Test(arguments: ["CC0", "CC-BY", "OFL", "MIT", "BSD", "Apache-2.0"])
    func allowedLicensePasses(license: String) {
        #expect(Credits.problems(in: [Self.entry { $0.license = license }]).isEmpty)
    }

    @Test(arguments: ["CC-BY-SA", "CC-BY-ND"])
    func shareAlikeNoDerivsMustBeUnmodified(license: String) {
        #expect(Credits.problems(in: [Self.entry { $0.license = license }]).isEmpty)
        #expect(!Credits.problems(in: [Self.entry { $0.license = license; $0.modified = true; $0.modifiedNote = "cropped" }]).isEmpty)
    }

    @Test func modifiedNeedsNote() {
        #expect(!Credits.problems(in: [Self.entry { $0.modified = true }]).isEmpty)
        #expect(Credits.problems(in: [Self.entry { $0.modified = true; $0.modifiedNote = "recolored" }]).isEmpty)
    }

    @Test func missingFieldsFail() {
        #expect(!Credits.problems(in: [Self.entry { $0.files = [] }]).isEmpty)
        #expect(!Credits.problems(in: [Self.entry { $0.author = " " }]).isEmpty)
        #expect(!Credits.problems(in: [Self.entry { $0.attribution = "" }]).isEmpty)
        #expect(!Credits.problems(in: [Self.entry { $0.dateAdded = "" }]).isEmpty)
    }

    @Test func thirdPartyNeedsUrls() {
        #expect(!Credits.problems(in: [Self.entry { $0.sourceURL = "nope" }]).isEmpty)
        #expect(!Credits.problems(in: [Self.entry { $0.licenseURL = "" }]).isEmpty)
    }

    @Test func selfMadeNeedsNoUrlsButMustMatchLicense() {
        let ok = Self.entry { $0.selfMade = true; $0.license = "Self-made"; $0.sourceURL = ""; $0.licenseURL = "" }
        #expect(Credits.problems(in: [ok]).isEmpty)
        #expect(!Credits.problems(in: [Self.entry { $0.selfMade = true }]).isEmpty)
        #expect(!Credits.problems(in: [Self.entry { $0.license = "Self-made" }]).isEmpty)
    }

    @Test func personalUseLicencesAreAccepted() {
        for l in ["CC-BY-NC", "CreativeML-OpenRAIL-M", "Research-only"] { #expect(Credits.problems(in: [Self.entry { $0.license = l }]).isEmpty, "\(l)") }
    }

    @Test func problemsReportEveryBadEntry() {
        let bad = Self.entry { $0.license = "Unknown" }
        #expect(Credits.problems(in: [bad, Self.entry(), bad]).count == 2)
    }

    // MARK: coverage
    @Test func uncoveredReportsMissingFiles() {
        let e = [Self.entry { $0.files = ["a.png", "b.png"] }]
        #expect(Credits.uncovered(files: ["a.png", "c.png", "b.png", "d.png"], entries: e) == ["c.png", "d.png"])
        #expect(Credits.uncovered(files: [], entries: e).isEmpty)
        #expect(Credits.uncovered(files: ["x"], entries: []) == ["x"])
    }

    @Test func decodeRoundTrips() throws {
        let data = try JSONEncoder().encode([Self.entry()])
        #expect(try Credits.decode(data) == [Self.entry()])
    }

    @Test func decodeRejectsGarbage() {
        #expect(throws: (any Error).self) { try Credits.decode(Data("{".utf8)) }
    }
}
