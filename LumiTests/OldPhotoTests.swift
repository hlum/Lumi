import CoreImage
import Foundation
import Testing
@testable import Lumi

struct OldPhotoTests {
    static func gray(_ w: CGFloat = 100, _ h: CGFloat = 80) -> CIImage { CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) }
    static func color() -> CIImage { CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 80)) }

    @Test func grayAndColorImagesAreToldApart() {
        #expect(OldPhotoRestore.isMostlyGray(Self.gray()))
        #expect(!OldPhotoRestore.isMostlyGray(Self.color()))
        #expect(!OldPhotoRestore.isMostlyGray(CIImage(color: .clear).cropped(to: .zero)))
    }

    @Test func slightTintStillCountsAsGrayButStrongTintDoesNot() {
        #expect(OldPhotoRestore.isMostlyGray(CIImage(color: CIColor(red: 0.52, green: 0.5, blue: 0.48)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))))
        #expect(!OldPhotoRestore.isMostlyGray(CIImage(color: CIColor(red: 0.7, green: 0.5, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))))
    }

    @Test func planColorizesOnlyGrayPhotosAndOnlyWhenTheModelExists() {
        #expect(OldPhotoRestore.plan(for: Self.gray(), canUpscale: true, canColorize: true).colorize == 1)
        #expect(OldPhotoRestore.plan(for: Self.color(), canUpscale: true, canColorize: true).colorize == nil)
        #expect(OldPhotoRestore.plan(for: Self.gray(), canUpscale: true, canColorize: false).colorize == nil)
    }

    @Test func planUpscalesSmallPhotosByTheLargestSafeFactor() {
        #expect(OldPhotoRestore.plan(for: Self.gray(400, 300), canUpscale: true, canColorize: false).upscale == 4)
        #expect(OldPhotoRestore.plan(for: Self.gray(900, 600), canUpscale: true, canColorize: false).upscale == 2)
        #expect(OldPhotoRestore.plan(for: Self.gray(1800, 1200), canUpscale: true, canColorize: false).upscale == nil)
        #expect(OldPhotoRestore.plan(for: Self.gray(400, 300), canUpscale: false, canColorize: false).upscale == nil)
    }

    @Test func applyWritesAllStepsAndReplacesEarlierOnes() {
        var doc = EditDocument(); doc.adjust = AdjustParams(brightness: 0.9); doc.exposure = 0.3
        let out = OldPhotoRestore.apply(OldPhotoRestore.Plan(adjust: AdjustParams(contrast: 0.2), upscale: 2, colorize: 1), to: doc)
        #expect(out.adjust == AdjustParams(contrast: 0.2) && out.upscale == 2 && out.colorize == 1 && out.exposure == 0.3)
        let none = OldPhotoRestore.apply(OldPhotoRestore.Plan(adjust: AdjustParams(contrast: 0.2), upscale: nil, colorize: nil), to: out)
        #expect(none.upscale == nil && none.colorize == nil)
    }

    @Test func colorizeComesBeforeUpscaleInTheOperationOrder() {
        let out = OldPhotoRestore.apply(OldPhotoRestore.Plan(adjust: AdjustParams(contrast: 0.2), upscale: 2, colorize: 1), to: EditDocument())
        let kinds = out.operations.map(\.kind)
        #expect(kinds.firstIndex(of: .colorize)! < kinds.firstIndex(of: .upscale)!)
    }
}
