import AVFoundation
import CoreImage
import Foundation
import Testing
@testable import Lumi

@MainActor
struct VideoEditorModelTests {
    static func movie(_ seconds: Double) async throws -> URL {
        try await StillVideo.make(CIImage(color: CIColor(red: 0.3, green: 0.6, blue: 0.9)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)), seconds: seconds, size: CGSize(width: 64, height: 64))
    }

    @Test func addingVideoCreatesASelectedClipOfTheRightLength() async throws {
        let m = VideoEditorModel()
        await m.addVideo(try await Self.movie(2))
        #expect(m.timeline.clips.count == 1 && abs(m.timeline.duration - 2) < 0.15 && m.selected == m.timeline.clips[0].id)
        #expect(m.canUndo)
    }

    @Test func unusableFilesReportAnErrorAndChangeNothing() async {
        let m = VideoEditorModel()
        await m.addVideo(URL(fileURLWithPath: "/nonexistent.mov"))
        #expect(m.timeline.isEmpty && m.error != nil)
    }

    @Test func splitDuplicateDeleteAndUndo() async throws {
        let m = VideoEditorModel()
        await m.addVideo(try await Self.movie(2))
        m.seek(1); m.splitAtPlayhead()
        #expect(m.timeline.clips.count == 2)
        m.selected = m.timeline.clips[0].id; m.duplicateSelected()
        #expect(m.timeline.clips.count == 3)
        m.deleteSelected()
        #expect(m.timeline.clips.count == 2)
        m.undo(); #expect(m.timeline.clips.count == 3)
        m.undo(); m.undo(); #expect(m.timeline.clips.count == 1)
        m.redo(); #expect(m.timeline.clips.count == 2)
    }

    @Test func splitOutsideTheClipSetsAnErrorAndKeepsTheTimeline() async throws {
        let m = VideoEditorModel()
        await m.addVideo(try await Self.movie(1))
        m.seek(0.01); m.splitAtPlayhead()
        #expect(m.timeline.clips.count == 1 && m.error != nil)
    }

    @Test func seekClampsToTheTimeline() async throws {
        let m = VideoEditorModel()
        await m.addVideo(try await Self.movie(1))
        m.seek(99); #expect(abs(m.playhead - m.timeline.duration) < 1e-9)
        m.seek(-5); #expect(m.playhead == 0)
    }

    @Test func speedAndTransitionApplyToTheSelectedClipOnly() async throws {
        let m = VideoEditorModel()
        await m.addVideo(try await Self.movie(2)); await m.addVideo(try await Self.movie(2))
        m.selected = m.timeline.clips[1].id
        m.setSpeed(2); m.setTransition(.fade)
        #expect(m.timeline.clips[1].speed == 2 && m.timeline.clips[1].transition == .fade)
        #expect(m.timeline.clips[0].speed == 1 && m.timeline.clips[0].transition == .none)
    }

    @Test func photosJoinTheTimelineAsTimedClips() async throws {
        let m = VideoEditorModel()
        await m.addPhoto(CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)), seconds: 1)
        #expect(m.timeline.clips.count == 1 && m.timeline.clips[0].isPhoto && abs(m.timeline.duration - 1) < 1e-9)
    }

    @Test func playerItemFollowsTheTimeline() async throws {
        let m = VideoEditorModel()
        await m.addVideo(try await Self.movie(1))
        await m.rebuildPlayer()
        #expect(m.playerItem != nil && abs(m.playerItem!.asset.duration.seconds - 1) < 0.15)
        m.undo(); await m.rebuildPlayer()
        #expect(m.playerItem == nil)
    }

    @Test func exportProducesAPlayableMP4() async throws {
        let m = VideoEditorModel()
        await m.addVideo(try await Self.movie(1))
        m.export.resolution = .p720
        let url = try #require(await m.exportVideo())
        let a = AVURLAsset(url: url)
        #expect(abs(try await a.load(.duration).seconds - 1) < 0.2)
        #expect(!m.isExporting)
        #expect(await VideoEditorModel().exportVideo() == nil)             // nothing to export
    }

    @Test func draftCapturesTimelineAndExportChoices() async throws {
        let m = VideoEditorModel()
        await m.addVideo(try await Self.movie(1)); m.export.fps = 60
        #expect(m.draft.timeline == m.timeline && m.draft.export.fps == 60)
    }
}
