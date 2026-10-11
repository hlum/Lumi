import CoreText
import Foundation
import UIKit

struct BundledFont: Codable, Equatable, Identifiable {
    var name: String
    var postScript: String
    var file: String
    var id: String { postScript }
}

/// Bundled OFL fonts, registered with Core Text at launch (no Info.plist list to keep in sync).
enum FontLibrary {
    static let directory = Bundle.main.resourceURL?.appendingPathComponent("Content/Fonts")

    static let fonts: [BundledFont] = directory.flatMap { try? Data(contentsOf: $0.appendingPathComponent("catalog.json")) }
        .flatMap { try? JSONDecoder().decode([BundledFont].self, from: $0) } ?? []

    /// System fonts offered alongside the bundled ones.
    static let system: [BundledFont] = [
        BundledFont(name: "Helvetica Bold", postScript: "HelveticaNeue-Bold", file: ""),
        BundledFont(name: "Georgia", postScript: "Georgia", file: ""),
        BundledFont(name: "Menlo", postScript: "Menlo-Regular", file: ""),
        BundledFont(name: "Chalkboard", postScript: "ChalkboardSE-Bold", file: ""),
    ]

    static var all: [BundledFont] { system + fonts }

    @discardableResult
    static func registerBundled() -> Int {
        guard let dir = directory else { return 0 }
        var n = 0
        for f in fonts {
            var err: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(dir.appendingPathComponent(f.file) as CFURL, .process, &err) { n += 1 }
            else if let e = err?.takeRetainedValue(), CFErrorGetCode(e) == CTFontManagerError.alreadyRegistered.rawValue { n += 1 }
        }
        return n
    }
}
