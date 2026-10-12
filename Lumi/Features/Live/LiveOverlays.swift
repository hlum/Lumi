import Foundation

/// Text and stickers on a Live Photo. Times are seconds into the ~3 s clip.
struct LiveOverlays: Codable, Equatable {
    static let maxTexts = 3
    private(set) var items: [VideoOverlay] = []

    var textCount: Int { items.filter { if case .text = $0.content { true } else { false } }.count }

    /// Returns false when the limit of Live texts is reached.
    @discardableResult mutating func add(_ o: VideoOverlay) -> Bool {
        if case .text = o.content, textCount >= Self.maxTexts { return false }
        var o = o
        o.start = min(max(o.start, 0), LiveConvert.liveLength); o.end = min(max(o.end, o.start), LiveConvert.liveLength)
        items.append(o)
        return true
    }

    mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    func active(at t: Double) -> [VideoOverlay] { OverlayTimeline.active(items, at: t) }
}
