import Observation
import CoreGraphics
import Foundation

struct Watermark: Codable, Equatable, Identifiable {
    enum Kind: Codable, Equatable { case text(String), image(String) }
    var id = UUID()
    var name: String
    var kind: Kind
    var opacity = 0.5
    var size = 0.08            // fraction of image height
    var isTiled = false
    var tileSpacing = 1.5      // multiple of the mark's own size
    var tileAngle = -0.5       // radians
}

enum TimeStampStyle: String, Codable, CaseIterable { case film, digital, plain }

enum WatermarkMath {
    /// Centers (normalized, top-left origin) for a tiled watermark. Staggers alternate rows; always covers the frame.
    static func tileCenters(imageAspect: Double, markAspect: Double, size: Double, spacing: Double) -> [CGPoint] {
        guard imageAspect > 0, markAspect > 0, size > 0, spacing > 0 else { return [] }
        let stepY = size * spacing, stepX = size * markAspect / imageAspect * spacing
        guard stepX > 0, stepY > 0, stepX < 4, stepY < 4 else { return [] }
        var out: [CGPoint] = []
        var row = 0, y = 0.0
        while y <= 1 + stepY {
            var x = row % 2 == 0 ? 0.0 : stepX / 2
            while x <= 1 + stepX, out.count < 5_000 { out.append(CGPoint(x: x, y: y)); x += stepX }
            y += stepY; row += 1
            if out.count >= 5_000 { break }      // guard against absurdly small marks
        }
        return out
    }

    static func timeStamp(_ date: Date, style: TimeStampStyle, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let (y, mo, d, h, mi) = (c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        switch style {
        case .film: return String(format: "'%02d %02d %02d", y % 100, mo, d)
        case .digital: return String(format: "%04d/%02d/%02d %02d:%02d", y, mo, d, h, mi)
        case .plain: return String(format: "%04d-%02d-%02d", y, mo, d)
        }
    }
}

/// Saved watermarks for reuse.
struct WatermarkLibrary: Codable, Equatable {
    private(set) var items: [Watermark] = []
    mutating func save(_ w: Watermark) {
        if let i = items.firstIndex(where: { $0.id == w.id }) { items[i] = w } else { items.append(w) }
    }
    mutating func delete(_ id: UUID) { items.removeAll { $0.id == id } }
}

/// Saved watermarks, kept in one JSON file so they can be reused on any photo.
@Observable @MainActor
final class WatermarkBox {
    private(set) var library: WatermarkLibrary
    private let url: URL?
    nonisolated static var defaultURL: URL { URL.applicationSupportDirectory.appendingPathComponent("watermarks.json") }

    init(url: URL? = WatermarkBox.defaultURL) {
        self.url = url
        if let url, let d = try? Data(contentsOf: url), let l = try? JSONDecoder().decode(WatermarkLibrary.self, from: d) { library = l } else { library = WatermarkLibrary() }
    }

    func save(_ w: Watermark) { library.save(w); persist() }
    func delete(_ id: UUID) { library.delete(id); persist() }

    private func persist() {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(library).write(to: url, options: .atomic)
    }
}
