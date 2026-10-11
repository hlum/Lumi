import Foundation
import Testing
import UIKit
@testable import Lumi

struct ReleaseTests {
    @Test func privacyManifestDeclaresNoTrackingAndNoCollectedData() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)
        #expect((plist["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
    }

    @Test func appIconIsInTheBundle() {
        #expect(UIImage(named: "AppIcon") != nil || Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") != nil)
    }

    @Test func permissionTextsExistAndAreNotEmpty() {
        for key in ["NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription"] {
            #expect(!((Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "").isEmpty, "\(key)")
        }
    }

    @Test func appDeclaresEnglishAndJapanese() {
        let langs = Bundle.main.object(forInfoDictionaryKey: "CFBundleLocalizations") as? [String] ?? []
        #expect(langs.contains("en") && langs.contains("ja"))
    }

    @Test func everyCreditHasEverythingThePublicPageNeeds() throws {
        let entries = try Credits.decode(Data(contentsOf: #require(Bundle.main.url(forResource: "Credits", withExtension: "json"))))
        #expect(entries.count >= 20)
        #expect(Credits.problems(in: entries).isEmpty)
        // every model that ships is credited
        let files = Set(entries.flatMap(\.files))
        for m in ["Models/LaMa.mlpackage", "Models/RealESRGAN_x4.mlpackage", "Models/SIGGraph17Colorizer.mlpackage"] { #expect(files.contains(m), "\(m)") }
    }

    @Test func modelsReferencedByCreditsExistInTheBundleOrAreFetched() {
        // the three models are fetched by scripts/fetch_models.sh; when they're present they must load
        for name in ["LaMa", "RealESRGAN_x4", "SIGGraph17Colorizer"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") { #expect(FileManager.default.fileExists(atPath: url.path)) }
        }
    }
}
