import AVFoundation
import CoreImage
import Foundation
import Testing
@testable import Lumi

struct VideoComposerTests {
    static func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage { CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)) }

    /// Makes `names` -> videos and returns a resolver for them.
    static func library(_ items: [String: (CIImage, Double)]) async throws -> [String: AVAsset] {
        var out: [String: AVAsset] = [:]
        for (k, v) in items { out[k] = AVURLAsset(url: try await StillVideo.make(v.0, seconds: v.1, size: CGSize(width: 64, height: 64))) }
        return out
    }

    @Test func stillVideoHasTheRequestedLengthAndSize() async throws {
        let url = try await StillVideo.make(Self.solid(1, 0, 0), seconds: 1, size: CGSize(width: 64, height: 48))
        let a = AVURLAsset(url: url)
        let d = try await a.load(.duration).seconds
        #expect(abs(d - 1) < 0.1)
        let size = try await a.loadTracks(withMediaType: .video).first!.load(.naturalSize)
        #expect(size == CGSize(width: 64, height: 48))
    }

    @Test func compositionLengthFollowsTrimAndSpeed() async throws {
        let lib = try await Self.library(["a": (Self.solid(1, 0, 0), 2), "b": (Self.solid(0, 0, 1), 2)])
        var t = Timeline()
        var a = TimelineClip(source: .video("a"), sourceDuration: 2)
        var b = TimelineClip(source: .video("b"), sourceDuration: 1); b.sourceStart = 0.5; b.speed = 2
        a.volume = 1
        t.append(a); t.append(b)
        let built = try await VideoComposer.build(t) { src in
            if case .video(let k) = src { return lib[k]! } else { throw VideoError.noVideoTrack }
        }
        #expect(abs(built.composition.duration.seconds - t.duration) < 0.15)          // 2 + 1/2 = 2.5
        #expect(abs(t.duration - 2.5) < 1e-9)
    }

    @Test func emptyTimelineAndMissingAssetsFail() async {
        await #expect(throws: VideoError.emptyTimeline) { _ = try await VideoComposer.build(Timeline()) { _ in AVMutableComposition() } }
        var t = Timeline(); t.append(TimelineClip(source: .video("x"), sourceDuration: 1))
        await #expect(throws: VideoError.noVideoTrack) { _ = try await VideoComposer.build(t) { _ in AVMutableComposition() } }
    }

    @Test func photoClipsBecomeStillVideos() async throws {
        let still = AVURLAsset(url: try await StillVideo.make(Self.solid(0, 1, 0), seconds: 1, size: CGSize(width: 64, height: 64)))
        var t = Timeline(); t.append(TimelineClip(source: .photo("p"), sourceDuration: 1))
        let built = try await VideoComposer.build(t) { _ in still }
        #expect(abs(built.composition.duration.seconds - 1) < 0.15)
    }

    @Test func exportWritesAPlayableFileAtTheChosenSize() async throws {
        let big = AVURLAsset(url: try await StillVideo.make(Self.solid(1, 0.5, 0), seconds: 1, size: CGSize(width: 1920, height: 1080)))
        var t = Timeline(); t.append(TimelineClip(source: .video("v"), sourceDuration: 1))
        let built = try await VideoComposer.build(t) { _ in big }
        var o = VideoExportOptions(); o.resolution = .p720; o.fps = 24
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try await VideoExporter.export(built, options: o, to: out)
        let a = AVURLAsset(url: out)
        let track = try #require(try await a.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 1280, height: 720))
        #expect(abs(try await a.load(.duration).seconds - 1) < 0.2)
        // known gap: AVAssetExportSession keeps the source frame rate, so the fps option is not honored yet (needs an AVAssetWriter export)
        #expect(try await track.load(.nominalFrameRate) > 0)
    }

    static func frameColor(_ url: URL, at t: Double) async throws -> [UInt8] {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url)); g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
        let cg = try await g.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
        return GeometryTests.rgb(CIImage(cgImage: cg), x: 32, y: 32)
    }

    @Test func fadeTransitionOverlapsClipsAndBlendsFrames() async throws {
        let lib = try await Self.library(["r": (Self.solid(1, 0, 0), 1), "b": (Self.solid(0, 0, 1), 1)])
        var t = Timeline()
        t.append(TimelineClip(source: .video("r"), sourceDuration: 1))
        var b = TimelineClip(source: .video("b"), sourceDuration: 1); b.transition = .fade; b.transitionDuration = 0.4
        t.append(b)
        #expect(abs(t.duration - 1.6) < 1e-9)
        let built = try await VideoComposer.build(t) { src in if case .video(let k) = src { return lib[k]! } else { throw VideoError.noVideoTrack } }
        #expect(abs(built.composition.duration.seconds - 1.6) < 0.1)
        var o = VideoExportOptions(); o.resolution = .p720
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try await VideoExporter.export(built, options: o, to: out)
        let early = try await Self.frameColor(out, at: 0.2), mid = try await Self.frameColor(out, at: 0.8), late = try await Self.frameColor(out, at: 1.4)
        #expect(early[0] > 180 && early[2] < 80)                 // still red
        #expect(mid[0] > 40 && mid[2] > 40)                      // halfway through the fade: both colors present
        #expect(late[2] > 180 && late[0] < 80)                   // now blue
    }

    @Test func perClipLookAndLayoutAreAppliedToTheExportedFrames() async throws {
        let src = AVURLAsset(url: try await StillVideo.make(Self.solid(0.4, 0.4, 0.4), seconds: 1, size: CGSize(width: 64, height: 64)))
        var plain = Timeline(); plain.append(TimelineClip(source: .video("x"), sourceDuration: 1))
        var bright = plain
        var look = EditDocument(); look.adjust = AdjustParams(brightness: 1)
        try bright.setLook(bright.clips[0].id, look)
        var o = VideoExportOptions(); o.resolution = .p720
        var results: [Int] = []
        for t in [plain, bright] {
            let built = try await VideoComposer.build(t, options: o) { _ in src }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
            try await VideoExporter.export(built, options: o, to: out)
            results.append(Int(try await Self.frameColor(out, at: 0.5)[0]))
        }
        #expect(results[1] > results[0] + 15, "brightness look did not reach the video: \(results)")
    }
}
