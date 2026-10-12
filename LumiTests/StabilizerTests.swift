import CoreImage
import Testing
@testable import Lumi

struct StabilizerTests {
    @Test func pathAccumulatesAndSmoothingFlattensJitter() {
        let motion = (0..<40).map { FrameMotion(dx: $0 % 2 == 0 ? 6 : -6, dy: 0, rotation: 0) }      // shaking, no net travel
        let p = Stabilizer.path(motion), s = Stabilizer.smooth(p, radius: 5)
        let rawSpan = p.map(\.dx).max()! - p.map(\.dx).min()!, smoothSpan = s[5..<35].map(\.dx).max()! - s[5..<35].map(\.dx).min()!
        #expect(smoothSpan < rawSpan / 3)
        #expect(Stabilizer.smooth(p, radius: 0) == p && Stabilizer.smooth([], radius: 3).isEmpty)
    }

    @Test func intentionalPansSurvive() {
        let pan = Array(repeating: FrameMotion(dx: 5, dy: 0, rotation: 0), count: 60)
        let c = Stabilizer.corrections(pan, radius: 10)
        #expect(c[30].dx.magnitude < 0.5)                 // steady pan: no correction needed mid-clip
        #expect(Stabilizer.corrections([], radius: 3).isEmpty)
    }

    @Test func correctionsCancelTheShake() {
        let motion = (0..<60).map { FrameMotion(dx: $0 % 2 == 0 ? 8 : -8, dy: 0, rotation: 0) }
        let raw = Stabilizer.path(motion), c = Stabilizer.corrections(motion, radius: 8)
        let fixed: [Double] = zip(raw, c).map { $0.dx + $1.dx }
        #expect(fixed[10..<50].max()! - fixed[10..<50].min()! < 2)
    }

    @Test func cropScaleCoversTheLargestCorrection() {
        let c = [FrameMotion(dx: 20, dy: -10, rotation: 0), FrameMotion(dx: -5, dy: 0, rotation: 0)]
        #expect(abs(Stabilizer.cropScale(c, frame: CGSize(width: 200, height: 100)) - 1.2) < 1e-9)
        #expect(Stabilizer.cropScale([], frame: CGSize(width: 200, height: 100)) == 1)
        #expect(Stabilizer.cropScale(c, frame: .zero) == 1)
    }

    @Test func applyKeepsTheFrameSize() {
        let f = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 60))
        #expect(Stabilizer.apply(FrameMotion(dx: 7, dy: -3, rotation: 0.02), scale: 1.1, to: f).extent == f.extent)
    }

    @Test func registrationFindsAShift() {
        // distinct blocks drawn at a known offset, so registration has real structure to lock onto
        func scene(shift: CGFloat) -> CIImage {
            let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            for (i, r) in [CGRect(x: 30, y: 40, width: 30, height: 20), CGRect(x: 90, y: 100, width: 40, height: 40), CGRect(x: 140, y: 30, width: 25, height: 50), CGRect(x: 50, y: 130, width: 20, height: 30)].enumerated() {
                ctx.setFillColor(gray: CGFloat(i) * 0.2, alpha: 1); ctx.fill(r.offsetBy(dx: shift, dy: 0))
            }
            return CIImage(cgImage: ctx.makeImage()!)
        }
        let m = Stabilizer.motion(from: scene(shift: 0), to: scene(shift: 12))
        #expect(m != nil && abs(abs(m!.dx) - 12) < 3, "got \(String(describing: m))")
    }
}

struct FrameAnalysisTrackTests {
    func face(_ x: CGFloat, _ y: CGFloat) -> FaceInfo { FaceInfo(box: CGRect(x: x, y: y, width: 0.2, height: 0.2), landmarks: ["nose": [CGPoint(x: 0.5, y: 0.5)]]) }

    @Test func smoothingShrinksJitter() {
        var t = FrameAnalysisTrack()
        var raw: [CGFloat] = [], smooth: [CGFloat] = []
        for i in 0..<30 {
            let x = 0.4 + (i % 2 == 0 ? 0.01 : -0.01)
            raw.append(x); smooth.append(t.update([face(x, 0.4)])[0].box.minX)
        }
        func span(_ a: ArraySlice<CGFloat>) -> CGFloat { a.max()! - a.min()! }
        #expect(span(smooth[10...]) < span(raw[10...]) / 2)
    }

    @Test func aJumpIsANewShotAndFacesAreNotMixed() {
        var t = FrameAnalysisTrack()
        _ = t.update([face(0.1, 0.1)])
        #expect(t.update([face(0.8, 0.8)])[0].box.minX == 0.8)             // too far: taken as is
        #expect(t.update([]).isEmpty && t.last.isEmpty)
        var two = FrameAnalysisTrack()
        _ = two.update([face(0.1, 0.1), face(0.6, 0.6)])
        let out = two.update([face(0.62, 0.6), face(0.12, 0.1)])            // order swapped between frames
        #expect(abs(out[0].box.minX - 0.6) < 0.05 && abs(out[1].box.minX - 0.1) < 0.05)
    }

    @Test func zeroSmoothingIsRaw() {
        var t = FrameAnalysisTrack(); t.smoothing = 0
        _ = t.update([face(0.4, 0.4)])
        #expect(t.update([face(0.45, 0.4)])[0].box.minX == 0.45)
    }
}
