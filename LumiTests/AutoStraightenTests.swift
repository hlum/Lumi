import CoreImage
import Foundation
import Testing
@testable import Lumi

struct AutoStraightenTests {
    /// Sky over ground with a sharp horizon, then the whole picture rotated by `degrees` (counter-clockwise positive).
    static func scene(tilt degrees: Double) -> CIImage {
        let w = 800.0, h = 600.0
        let sky = CIImage(color: CIColor(red: 0.5, green: 0.7, blue: 1)).cropped(to: CGRect(x: -400, y: h / 2, width: w + 800, height: h))
        let ground = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.1)).cropped(to: CGRect(x: -400, y: -h / 2, width: w + 800, height: h))
        // add some texture so the detector has gradients to work with
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: CGRect(x: -400, y: -300, width: w + 800, height: h * 2))
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.08, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.08, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0.08, w: 0)])
        let base = noise.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: sky.composited(over: ground)])
        let rot = CGAffineTransform(translationX: w / 2, y: h / 2).rotated(by: degrees * .pi / 180).translatedBy(x: -w / 2, y: -h / 2)
        return base.transformed(by: rot).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }

    @Test func levelHorizonNeedsNoCorrection() {
        let a = AutoStraighten.angle(for: Self.scene(tilt: 0))
        #expect(a == nil || abs(a!) < 1)
    }

    @Test func aTiltedHorizonIsDetectedWithTheRightSign() throws {
        let cw = try #require(AutoStraighten.angle(for: Self.scene(tilt: -6)), "no horizon found")      // picture rotated clockwise by 6°
        let ccw = try #require(AutoStraighten.angle(for: Self.scene(tilt: 6)))
        #expect(abs(abs(cw) - 6) < 2.5 && abs(abs(ccw) - 6) < 2.5)
        #expect(cw * ccw < 0)                                                                    // opposite tilts give opposite corrections
    }

    @Test func applyingTheAngleLevelsTheHorizon() throws {
        let tilted = Self.scene(tilt: 8)
        let a = try #require(AutoStraighten.angle(for: tilted))
        let fixed = GeometryOps.apply(CropSpec(angle: a), to: tilted)
        let after = AutoStraighten.angle(for: fixed)
        #expect(after == nil || abs(after!) < 2.5, "still tilted: \(String(describing: after))")
    }

    @Test func imageWithNoHorizonGivesNilOrSmallAngle() {
        let flat = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 300))
        #expect(AutoStraighten.angle(for: flat) == nil)
    }
}
