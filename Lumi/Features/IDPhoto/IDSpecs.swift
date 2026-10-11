import CoreGraphics
import Foundation

struct IDSpec: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var widthMM: Double, heightMM: Double
    var headMin: Double, headMax: Double      // head height as a fraction of photo height
    var eyeLine: Double                       // eye line, fraction of photo height from the top
    var background: [Double]                  // rgb 0...1

    var aspect: Double { widthMM / heightMM }
    func pixels(dpi: Double = 300) -> (w: Int, h: Int) {
        (ExportSettings.pixels(widthMM, unit: .mm, dpi: dpi), ExportSettings.pixels(heightMM, unit: .mm, dpi: dpi))
    }

    static func load(_ data: Data) throws -> [IDSpec] { try JSONDecoder().decode([IDSpec].self, from: data) }
}

enum IDPhotoMath {
    /// Head box ≈ face box grown for hair and chin.
    static func headHeight(faceHeight: Double) -> Double { faceHeight * 1.3 }

    struct Crop: Equatable { var rect: CGRect; var fitsInImage: Bool }

    /// Crop (pixels, y-down) that puts the head at the spec's mid head size and the eyes on the eye line.
    /// `face` is the face box in pixels (y-down); `eyeY` the eye line's y in pixels.
    static func crop(face: CGRect, eyeY: Double, spec: IDSpec, image: CGSize) -> Crop? {
        guard face.width > 0, face.height > 0, image.width > 0, image.height > 0 else { return nil }
        let headFraction = (spec.headMin + spec.headMax) / 2
        let h = headHeight(faceHeight: Double(face.height)) / headFraction
        let w = h * spec.aspect
        let top = eyeY - spec.eyeLine * h
        let r = CGRect(x: Double(face.midX) - w / 2, y: top, width: w, height: h)
        return Crop(rect: r, fitsInImage: CGRect(origin: .zero, size: image).contains(r))
    }

    struct Check: Equatable { var headSizeOK: Bool, centeredOK: Bool, levelOK: Bool, eyeLineOK: Bool; var passes: Bool { headSizeOK && centeredOK && levelOK && eyeLineOK } }

    /// Compliance of a finished crop: `face`/`eyeY` in the cropped photo's own pixel space.
    static func check(face: CGRect, eyeY: Double, leftEye: CGPoint, rightEye: CGPoint, photo: CGSize, spec: IDSpec) -> Check {
        let head = headHeight(faceHeight: Double(face.height)) / Double(photo.height)
        let tilt = abs(atan2(Double(rightEye.y - leftEye.y), Double(rightEye.x - leftEye.x))) * 180 / .pi
        return Check(headSizeOK: head >= spec.headMin && head <= spec.headMax,
                     centeredOK: abs(Double(face.midX) / Double(photo.width) - 0.5) < 0.05,
                     levelOK: tilt <= 5,
                     eyeLineOK: abs(eyeY / Double(photo.height) - spec.eyeLine) < 0.05)
    }

    /// Print sheet: as many copies of the photo as fit on the paper, centered, with a gap.
    static func sheet(paperMM: CGSize, photoMM: CGSize, gapMM: Double = 2) -> [CGRect] {
        guard photoMM.width > 0, photoMM.height > 0 else { return [] }
        let cols = max(Int((Double(paperMM.width) + gapMM) / (Double(photoMM.width) + gapMM)), 0)
        let rows = max(Int((Double(paperMM.height) + gapMM) / (Double(photoMM.height) + gapMM)), 0)
        guard cols > 0, rows > 0 else { return [] }
        let usedW = Double(cols) * Double(photoMM.width) + Double(cols - 1) * gapMM, usedH = Double(rows) * Double(photoMM.height) + Double(rows - 1) * gapMM
        let x0 = (Double(paperMM.width) - usedW) / 2, y0 = (Double(paperMM.height) - usedH) / 2
        return (0..<rows).flatMap { r in (0..<cols).map { c in
            CGRect(x: x0 + Double(c) * (Double(photoMM.width) + gapMM), y: y0 + Double(r) * (Double(photoMM.height) + gapMM), width: Double(photoMM.width), height: Double(photoMM.height))
        } }
    }
}
