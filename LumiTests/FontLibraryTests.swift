import CoreText
import Foundation
import Testing
import UIKit
@testable import Lumi

struct FontLibraryTests {
    init() { FontLibrary.registerBundled() }

    @Test func catalogHasTheBundledFonts() {
        #expect(FontLibrary.fonts.count >= 6)
        #expect(Set(FontLibrary.fonts.map(\.postScript)).count == FontLibrary.fonts.count)
    }

    @Test(arguments: FontLibrary.fonts.map(\.postScript))
    func everyBundledFontResolvesByPostScriptName(name: String) {
        #expect(UIFont(name: name, size: 20) != nil, "\(name) did not register")
    }

    @Test func everyFontFileAndItsLicenseShip() {
        for f in FontLibrary.fonts {
            #expect(FileManager.default.fileExists(atPath: FontLibrary.directory!.appendingPathComponent(f.file).path), "\(f.file)")
        }
        let ofl = (try? FileManager.default.contentsOfDirectory(atPath: FontLibrary.directory!.path))?.filter { $0.hasPrefix("OFL-") } ?? []
        #expect(ofl.count == FontLibrary.fonts.count)
    }

    @Test func systemFontsExistToo() {
        for f in FontLibrary.system { #expect(UIFont(name: f.postScript, size: 12) != nil, "\(f.postScript)") }
    }

    @Test func registeringTwiceIsHarmless() {
        let first = FontLibrary.registerBundled()
        #expect(FontLibrary.registerBundled() == first && first == FontLibrary.fonts.count)
    }

    @Test func bundledFontsRenderRealGlyphsIncludingJapanese() throws {
        var st = TextStyle(); st.fontName = "ZenMaruGothic-Bold"; st.size = 0.2; st.color = .black
        let jp = try #require(LayerRenderer.textImage("こんにちは", style: st, imageHeight: 400))
        var st2 = st; st2.fontName = "HelveticaNeue-Bold"
        let latin = try #require(LayerRenderer.textImage("こんにちは", style: st2, imageHeight: 400))
        #expect(jp.extent.width > 0 && jp.extent.height > 0 && latin.extent.width > 0)
    }

    @Test func creditsCoverEveryFontWithAnOFLEntry() throws {
        let data = try Data(contentsOf: #require(Bundle.main.url(forResource: "Credits", withExtension: "json")))
        let entries = try Credits.decode(data)
        for f in FontLibrary.fonts {
            let e = try #require(entries.first { $0.files.contains("Fonts/\(f.file)") }, "no credit for \(f.file)")
            #expect(e.license == "OFL" && e.attribution.contains("Copyright"))
        }
    }
}
