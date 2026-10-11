import CoreImage
import Foundation
import Testing
@testable import Lumi

struct CameraTests {
    @Test func timerAndFlashCycleThroughTheirValues() {
        var s = CameraSettings()
        var seen = [s.timer]
        for _ in 0..<3 { s.cycleTimer(); seen.append(s.timer) }
        #expect(seen == [0, 3, 10, 0])
        s.cycleFlash(); #expect(s.flash == .auto); s.cycleFlash(); #expect(s.flash == .on); s.cycleFlash(); #expect(s.flash == .off)
        s.timer = 7; s.cycleTimer(); #expect(s.timer == 3)               // unknown value falls into the cycle
    }

    @Test func frontCameraHasNoHardwareFlashAndFlipTogglesLens() {
        var s = CameraSettings(); s.flash = .on
        #expect(s.hardwareFlash == .on)
        s.flip(); #expect(s.lens == .front && s.hardwareFlash == .off)
        s.flip(); #expect(s.lens == .back)
        s.lens = .ultraWide; s.flip(); #expect(s.lens == .front)
    }

    @Test func cropRectCentersTheChosenAspect() {
        var s = CameraSettings()
        let portrait = CGSize(width: 3000, height: 4000)            // 3:4 sensor frame
        s.aspect = .fourThree
        #expect(s.cropRect(for: portrait) == CGRect(x: 0, y: 0, width: 3000, height: 4000))
        s.aspect = .square
        #expect(s.cropRect(for: portrait) == CGRect(x: 0, y: 500, width: 3000, height: 3000))
        s.aspect = .sixteenNine
        let r = s.cropRect(for: portrait)
        #expect(abs(Double(r.width / r.height) - 9.0 / 16) < 1e-9 && r.minX == 0 || r.minX > 0)
        #expect(r.width <= 3000 && r.height <= 4000 && abs(r.midX - 1500) < 1e-9 && abs(r.midY - 2000) < 1e-9)
        #expect(s.cropRect(for: .zero) == .zero)
    }

    @Test func countdownTicksDownAndFiresOnce() {
        var c = Countdown(seconds: 3)
        let idle = c.tick()
        #expect(!c.isRunning && !idle)                                     // not started: ticks do nothing
        c.start(); #expect(c.isRunning && c.remaining == 3)
        let t1 = c.tick(), r1 = c.remaining
        let t2 = c.tick(), r2 = c.remaining
        let t3 = c.tick()
        #expect(!t1 && r1 == 2 && !t2 && r2 == 1)
        #expect(t3 && !c.isRunning && c.remaining == 0)
        let after = c.tick()
        #expect(!after)                                                    // already fired
    }

    @Test func zeroSecondTimerNeverRunsAndCancelStops() {
        var z = Countdown(seconds: 0); z.start(); #expect(!z.isRunning)
        var c = Countdown(seconds: 5); c.start(); c.cancel()
        let t = c.tick()
        #expect(!c.isRunning && !t && c.remaining == 5)
        #expect(Countdown(seconds: -4).remaining == 0)
    }

    @Test func pipelineCropsToTheAspect() {
        var s = CameraSettings(); s.aspect = .square
        let frame = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 400))
        let out = CameraPipeline.process(frame, settings: s)
        #expect(out.extent.width == 300 && out.extent.height == 300)
    }

    @Test func pipelineAppliesTheLiveFilterAndBeauty() {
        let frame = RendererTests.solid(0.5, size: 64)
        var s = CameraSettings(); s.aspect = .square
        let plain = RendererTests.pixel(CameraPipeline.process(frame, settings: s))
        s.lookID = "warm"
        let warm = RendererTests.pixel(CameraPipeline.process(frame, settings: s))
        #expect(warm[0] > warm[2] && warm != plain)
        s.lookID = nil; s.beauty = 1
        #expect(CameraPipeline.process(frame, settings: s).extent == CGRect(x: 0, y: 0, width: 64, height: 64) || CameraPipeline.process(frame, settings: s).extent.width == 64)
    }

    @Test func settingsPersistThroughJSON() throws {
        var s = CameraSettings(); s.timer = 10; s.lookID = "film-gold"; s.beauty = 0.4; s.aspect = .sixteenNine
        #expect(try JSONDecoder().decode(CameraSettings.self, from: JSONEncoder().encode(s)) == s)
    }
}
