import Foundation
import Testing
@testable import Lumi

struct LocalizationTests {
    /// Every user-visible string in the UI. Add new strings here and to Localizable.xcstrings with both languages.
    static let keys: [String] = ["About", "Add", "Add text", "Adjust", "Angle", "Black", "Blur", "Box", "Brush", "Clear", "Couldn't open that photo", "Couldn't remove that", "Couldn't save", "Credits", "Crop", "Cutout", "Edge shift", "Editor", "Edits you start appear here.", "Flip H", "Flip V", "Home", "License", "Mode", "No credits", "No drafts yet", "Off", "Photo", "Pick a photo", "Projects", "Redo", "Remove", "Removing…", "Reset", "Rotate", "Save", "Search tools", "Setting", "Settings", "Sky", "Soft edge", "Text", "Tool", "Tools", "Undo", "Undo stroke", "Version", "White"]

    static func bundle(_ lang: String) -> Bundle? {
        Bundle.main.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    @Test func japaneseBundleIsShipped() { #expect(Self.bundle("ja") != nil && Self.bundle("en") != nil) }

    @Test(arguments: keys)
    func everyKeyHasAJapaneseTranslation(key: String) throws {
        let ja = try #require(Self.bundle("ja"))
        let value = ja.localizedString(forKey: key, value: "__missing__", table: nil)
        #expect(value != "__missing__" && !value.isEmpty, "missing ja for '\(key)'")
        #expect(value != key, "ja for '\(key)' is untranslated")
    }

    @Test(arguments: keys)
    func everyKeyHasAnEnglishValue(key: String) throws {
        let en = try #require(Self.bundle("en"))
        #expect(en.localizedString(forKey: key, value: "__missing__", table: nil) != "__missing__", "missing en for '\(key)'")
    }
}
