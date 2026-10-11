import CoreImage
import Foundation
import Observation

struct CustomSticker: Codable, Equatable, Identifiable { var id: String; var name: String; var created: Date }

/// "My stickers": cut-out PNGs kept in the app's folder, with a small JSON index.
@Observable
final class CustomStickerStore: @unchecked Sendable {
    nonisolated(unsafe) static var shared = CustomStickerStore()
    static let prefix = "custom-"

    private(set) var items: [CustomSticker] = []
    private let directory: URL
    private let context = CIContext()
    private let lock = NSLock()

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("CustomStickers", isDirectory: true)) {
        self.directory = directory
        if let d = try? Data(contentsOf: directory.appendingPathComponent("index.json")), let i = try? JSONDecoder().decode([CustomSticker].self, from: d) { items = i }
    }

    static func isCustom(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// Bounds of the visible (non-transparent) pixels, in CI coordinates; nil when the image is fully transparent.
    static func visibleBounds(_ image: CIImage, context: CIContext = CIContext()) -> CGRect? {
        let e = image.extent
        let w = Int(e.width), h = Int(e.height)
        guard w > 0, h > 0, w * h < 120_000_000 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        context.render(image, toBitmap: &px, rowBytes: w * 4, bounds: e, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 8 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX >= 0 else { return nil }
        // the bitmap's first row is the top: flip to CI's bottom-left origin
        return CGRect(x: e.minX + CGFloat(minX), y: e.minY + CGFloat(h - 1 - maxY), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
    }

    /// Cuts a transparent picture down to its visible part and keeps it. Returns nil if nothing is visible.
    @discardableResult
    func add(cutout: CIImage, name: String = "") -> CustomSticker? {
        guard let box = Self.visibleBounds(cutout, context: context), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let trimmed = cutout.cropped(to: box.insetBy(dx: -2, dy: -2).intersection(cutout.extent))
        let id = Self.prefix + UUID().uuidString
        guard let png = context.pngRepresentation(of: trimmed, format: .RGBA8, colorSpace: space) else { return nil }
        lock.lock(); defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(id + ".png"), options: .atomic)
        } catch { return nil }
        let s = CustomSticker(id: id, name: name.isEmpty ? "Sticker \(items.count + 1)" : name, created: .now)
        items.append(s); persist()
        return s
    }

    func image(_ id: String) -> CIImage? {
        guard Self.isCustom(id), items.contains(where: { $0.id == id }) else { return nil }
        return CIImage(contentsOf: directory.appendingPathComponent(id + ".png"))
    }

    func remove(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        items.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(id + ".png"))
        persist()
    }

    private func persist() { try? JSONEncoder().encode(items).write(to: directory.appendingPathComponent("index.json"), options: .atomic) }
}
