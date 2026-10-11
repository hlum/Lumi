import AVFoundation
import CoreImage
import Foundation
import Testing
@testable import Lumi

struct ClipOpsTests {
    static func red() -> CIImage { CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 60)) }
    static func blue() -> CIImage { CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 60)) }
    static func at(_ i: CIImage, _ x: Int) -> [UInt8] { GeometryTests.rgb(i, x: x, y: 30) }

    // MARK: transitions
    @Test func endpointsAreExactlyTheTwoPictures() {
        for k in TransitionKind.allCases where k != .none {
            #expect(Self.at(Transitions.frame(k, from: Self.red(), to: Self.blue(), progress: 0), 50)[0] > 200, "\(k) start")
            #expect(Self.at(Transitions.frame(k, from: Self.red(), to: Self.blue(), progress: 1), 50)[2] > 200, "\(k) end")
        }
        #expect(Self.at(Transitions.frame(.none, from: Self.red(), to: Self.blue(), progress: 0.5), 50)[0] > 200)
        #expect(Self.at(Transitions.frame(.none, from: Self.red(), to: Self.blue(), progress: 1), 50)[2] > 200)
    }

    @Test func fadeMixesAtTheMidpoint() {
        let p = Self.at(Transitions.frame(.fade, from: Self.red(), to: Self.blue(), progress: 0.5), 50)
        #expect(p[0] > 60 && p[0] < 200 && p[2] > 60 && p[2] < 200)
    }

    @Test func wipeRevealsLeftToRight() {
        let f = Transitions.frame(.wipe, from: Self.red(), to: Self.blue(), progress: 0.5)
        #expect(Self.at(f, 20)[2] > 200 && Self.at(f, 80)[0] > 200)
    }

    @Test func slideLeftPushesTheOldPictureOut() {
        let f = Transitions.frame(.slideLeft, from: Self.red(), to: Self.blue(), progress: 0.5)
        #expect(Self.at(f, 20)[0] > 200 && Self.at(f, 80)[2] > 200)            // old on the left shrinking, new entering from the right
        let r = Transitions.frame(.slideRight, from: Self.red(), to: Self.blue(), progress: 0.5)
        #expect(Self.at(r, 20)[2] > 200 && Self.at(r, 80)[0] > 200)
    }

    @Test func everyKindKeepsTheOutgoingExtentAndClampsProgress() {
        for k in TransitionKind.allCases {
            #expect(Transitions.frame(k, from: Self.red(), to: Self.blue(), progress: 0.3).extent == Self.red().extent, "\(k)")
            #expect(Transitions.frame(k, from: Self.red(), to: Self.blue(), progress: -4).extent == Self.red().extent)
            #expect(Transitions.frame(k, from: Self.red(), to: Self.blue(), progress: 9).extent == Self.red().extent)
        }
    }

    @Test func overlapIsClampedToHalfOfTheShorterClip() {
        #expect(Transitions.overlap(clipA: 10, clipB: 10, requested: 0.5) == 0.5)
        #expect(Transitions.overlap(clipA: 0.6, clipB: 10, requested: 0.5) == 0.3)
        #expect(Transitions.overlap(clipA: 10, clipB: 0, requested: 0.5) == 0)
        #expect(Transitions.overlap(clipA: 10, clipB: 10, requested: -1) == 0)
    }

    @Test func progressRampsAndHandlesZeroDuration() {
        #expect(Transitions.progress(at: 1, start: 1, duration: 0.5) == 0)
        #expect(Transitions.progress(at: 1.25, start: 1, duration: 0.5) == 0.5)
        #expect(Transitions.progress(at: 3, start: 1, duration: 0.5) == 1 && Transitions.progress(at: 0, start: 1, duration: 0.5) == 0)
        #expect(Transitions.progress(at: 1, start: 1, duration: 0) == 1 && Transitions.progress(at: 0.9, start: 1, duration: 0) == 0)
    }

    // MARK: layout
    @Test func layoutFitsTheFrameOntoTheCanvasWithBackgroundBars() {
        var l = ClipOps.FrameLayout(); l.background = RGBA(r: 0, g: 1, b: 0, a: 1)
        let out = ClipOps.layout(Self.red(), l, canvas: CGSize(width: 100, height: 100))          // 100x60 into a square
        #expect(out.extent == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(GeometryTests.rgb(out, x: 50, y: 50)[0] > 200)                                       // picture in the middle
        #expect(GeometryTests.rgb(out, x: 50, y: 5)[1] > 200 && GeometryTests.rgb(out, x: 50, y: 95)[1] > 200)   // bars top and bottom
    }

    @Test func mirrorFlipsHorizontally() {
        let two = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 50, y: 0, width: 50, height: 60)).composited(over: Self.red())
        var l = ClipOps.FrameLayout(); l.mirror = true
        let out = ClipOps.layout(two, l, canvas: CGSize(width: 100, height: 60))
        #expect(Self.at(out, 10)[2] > 200 && Self.at(out, 90)[0] > 200)
    }

    @Test func cropAndRotateApplyBeforeFitting() {
        var l = ClipOps.FrameLayout(); l.crop = CropSpec(quarterTurns: 1)
        let out = ClipOps.layout(Self.red(), l, canvas: CGSize(width: 60, height: 100))              // rotated 90°: now 60x100, fills exactly
        #expect(GeometryTests.rgb(out, x: 30, y: 50)[0] > 200 && GeometryTests.rgb(out, x: 2, y: 2)[0] > 200)
    }

    // MARK: freeze + reverse (real video, run on device)
    /// A 1 s video that is red for the first half and blue for the second.
    static func redThenBlue() async throws -> AVURLAsset {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let ctx = CIContext()
        for i in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pb: CVPixelBuffer?; CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &pb)
            ctx.render(CIImage(color: i < 15 ? CIColor(red: 1, green: 0, blue: 0) : CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)), to: pb!)
            adaptor.append(pb!, withPresentationTime: CMTime(value: Int64(i), timescale: 30))
        }
        input.markAsFinished(); await writer.finishWriting()
        return AVURLAsset(url: url)
    }
    static func color(of asset: AVAsset, at t: Double) async throws -> [UInt8] {
        let g = AVAssetImageGenerator(asset: asset); g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
        let cg = try await g.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
        return GeometryTests.rgb(CIImage(cgImage: cg), x: 32, y: 32)
    }

    @Test func freezeFrameHoldsTheChosenMoment() async throws {
        let src = try await Self.redThenBlue()
        let frozen = AVURLAsset(url: try await ClipOps.freezeFrame(of: src, at: 0.8, hold: 1))      // 0.8 s is in the blue half
        #expect(abs(try await frozen.load(.duration).seconds - 1) < 0.15)
        let c = try await Self.color(of: frozen, at: 0.1)
        #expect(c[2] > 200 && c[0] < 60)
        let c2 = try await Self.color(of: frozen, at: 0.9)
        #expect(c2[2] > 200)                                                                          // still blue at the end
    }

    @Test func reversedClipPlaysBlueBeforeRed() async throws {
        let src = try await Self.redThenBlue()
        let rev = AVURLAsset(url: try await ClipOps.reversed(src))
        #expect(abs(try await rev.load(.duration).seconds - 1) < 0.15)
        let first = try await Self.color(of: rev, at: 0.1), last = try await Self.color(of: rev, at: 0.9)
        #expect(first[2] > 200 && first[0] < 60)
        #expect(last[0] > 200 && last[2] < 60)
    }

    @Test func reversingNothingFails() async {
        await #expect(throws: VideoError.noVideoTrack) { _ = try await ClipOps.reversed(AVMutableComposition()) }
    }
}
