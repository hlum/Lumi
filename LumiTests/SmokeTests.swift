import Foundation
import Testing
@testable import Lumi

struct SmokeTests {
    @Test func tabsAreHomeProjectsSettings() {
        #expect(RootTab.allCases.map(\.rawValue) == ["Home", "Projects", "Settings"])
    }

    @Test func tabSymbolsAreDistinctAndNonEmpty() {
        let symbols = RootTab.allCases.map(\.symbol)
        #expect(Set(symbols).count == symbols.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }

    @Test func bundledFixtureLoads() throws {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: "fixture", withExtension: "json"))
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(obj?["ok"] as? Bool == true)
    }

    @Test func appIsNotIPadTargeted() {
        let family = Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int] ?? [1]
        #expect(!family.contains(2))
    }
}

final class FixtureAnchor {}
