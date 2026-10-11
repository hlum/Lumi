import AVFoundation
import CoreImage
import Foundation
import Observation

@Observable @MainActor
final class VideoEditorModel {
    private var stack = UndoStack(Timeline())
    private var assets: [String: AVAsset] = [:]
    var playhead = 0.0
    var selected: UUID?
    var export = VideoExportOptions()
    private(set) var playerItem: AVPlayerItem?
    private(set) var isExporting = false
    private(set) var error: String?

    var timeline: Timeline { stack.current }
    var canUndo: Bool { stack.canUndo }
    var canRedo: Bool { stack.canRedo }
    var draft: VideoDraft { VideoDraft(timeline: timeline, export: export) }

    // MARK: edits (each is one undo step)

    private func edit(_ change: (inout Timeline) throws -> Void) {
        var t = stack.current
        do { try change(&t); stack.commit(t); error = nil; Task { await rebuildPlayer() } }
        catch { self.error = String(describing: error) }
    }

    func addVideo(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let d = try? await asset.load(.duration).seconds, d >= TimelineClip.minDuration else { error = "That video can't be used"; return }
        let key = url.absoluteString
        assets[key] = asset
        let clip = TimelineClip(source: .video(key), sourceDuration: d)
        edit { $0.append(clip) }
        selected = clip.id
    }

    func addPhoto(_ image: CIImage, seconds: Double = TimelineClip.photoDefault) async {
        let size = timelineSize()
        guard let url = try? await StillVideo.make(image, seconds: seconds, size: size) else { error = "That photo can't be used"; return }
        let key = "photo-" + UUID().uuidString
        assets[key] = AVURLAsset(url: url)
        let clip = TimelineClip(source: .photo(key), sourceDuration: seconds)
        edit { $0.append(clip) }
        selected = clip.id
    }

    /// Photos take the size of the first video clip, or 1080x1920 for an empty timeline.
    private func timelineSize() -> CGSize { CGSize(width: 1080, height: 1920) }

    func splitAtPlayhead() { edit { _ = try $0.split(at: playhead) } }
    func deleteSelected() { if let id = selected { edit { try $0.remove(id) }; selected = timeline.clips.first?.id } }
    func duplicateSelected() { if let id = selected { edit { try $0.duplicate(id) } } }
    func move(_ id: UUID, to index: Int) { edit { try $0.move(id, to: index) } }
    func setSpeed(_ s: Double) { if let id = selected { edit { try $0.setSpeed(id, s) } } }
    func setVolume(_ v: Double) { if let id = selected { edit { try $0.setVolume(id, v) } } }
    func setTransition(_ k: TransitionKind) { if let id = selected { edit { try $0.setTransition(id, k) } } }
    func setLook(_ look: EditDocument) { if let id = selected { edit { try $0.setLook(id, look) } } }

    func undo() { stack.undo(); Task { await rebuildPlayer() } }
    func redo() { stack.redo(); Task { await rebuildPlayer() } }

    func seek(_ t: Double) { playhead = min(max(t, 0), timeline.duration) }

    // MARK: playback and export

    func resolve(_ source: TimelineClip.Source) async throws -> AVAsset {
        switch source {
        case .video(let k), .photo(let k):
            guard let a = assets[k] else { throw VideoError.noVideoTrack }
            return a
        }
    }

    func rebuildPlayer() async {
        guard !timeline.isEmpty, let built = try? await VideoComposer.build(timeline, options: export, resolve: resolve) else { playerItem = nil; return }
        let item = AVPlayerItem(asset: built.composition)
        item.videoComposition = built.videoComposition; item.audioMix = built.audioMix
        playerItem = item
    }

    func exportVideo() async -> URL? {
        guard !timeline.isEmpty else { return nil }
        isExporting = true; defer { isExporting = false }
        do {
            let built = try await VideoComposer.build(timeline, options: export, resolve: resolve)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("lumi-\(UUID().uuidString).mp4")
            try await VideoExporter.export(built, options: export, to: url)
            return url
        } catch { self.error = String(describing: error); return nil }
    }
}
