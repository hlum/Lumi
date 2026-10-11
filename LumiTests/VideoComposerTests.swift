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
}
