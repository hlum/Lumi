import Foundation

/// Settings that outlive a session: where the editor's export starts, and how the app looks.
enum AppPrefs {
    enum Appearance: String, CaseIterable, Codable { case system, light, dark }

    private static var defaults: UserDefaults { .standard }

    static var format: ImageFormat {
        get { defaults.string(forKey: "export.format").flatMap(ImageFormat.init(rawValue:)) ?? .jpeg }
        set { defaults.set(newValue.rawValue, forKey: "export.format") }
    }
    static var quality: Double {
        get { defaults.object(forKey: "export.quality") as? Double ?? 0.9 }
        set { defaults.set(min(max(newValue, 0.3), 1), forKey: "export.quality") }
    }
    /// 0 = the photo's own size.
    static var maxLongSide: Int {
        get { defaults.integer(forKey: "export.maxLongSide") }
        set { defaults.set(newValue, forKey: "export.maxLongSide") }
    }
    static var appearance: Appearance {
        get { defaults.string(forKey: "look.appearance").flatMap(Appearance.init(rawValue:)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "look.appearance") }
    }

    /// A new editor session starts from the saved defaults.
    static func exportSettings() -> ExportSettings {
        var s = ExportSettings(); s.format = format; s.quality = quality; s.maxLongSide = maxLongSide == 0 ? nil : maxLongSide
        return s
    }
}
