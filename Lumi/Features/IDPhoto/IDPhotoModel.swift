import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import Photos
import UIKit

enum IDPhotoRenderer {
    /// The measurements of the first face, in the photo's pixels with a top-left origin.
    struct Subject: Equatable {
        var face: CGRect
        var eyeY: Double
        var leftEye: CGPoint, rightEye: CGPoint
    }

    static func subject(from face: FaceInfo, imageSize: CGSize) -> Subject? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let box = MakeupRenderer.faceBox(face)
        let faceRect = CGRect(x: box.minX * imageSize.width, y: box.minY * imageSize.height, width: box.width * imageSize.width, height: box.height * imageSize.height)
        func center(_ r: String) -> CGPoint? { FaceReshape.center(FaceReshape.points(face, r)).map { CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height) } }
        guard let a = center("leftEye"), let b = center("rightEye") else { return nil }
        let (l, r) = a.x < b.x ? (a, b) : (b, a)
        return Subject(face: faceRect, eyeY: Double(a.y + b.y) / 2, leftEye: l, rightEye: r)
    }

    /// The finished photo at the spec's pixel size: person cut out and placed on the background colour, framed by the spec's head rules.
    /// `personMask`: white = person (same extent as `image`); nil keeps the original background.
    static func render(_ image: CIImage, subject: Subject, spec: IDSpec, background: RGBA, personMask: CIImage?, dpi: Double = 300) -> CIImage? {
        let e = image.extent
        guard let crop = IDPhotoMath.crop(face: subject.face, eyeY: subject.eyeY, spec: spec, image: e.size) else { return nil }
        let (pw, ph) = spec.pixels(dpi: dpi)
        let bg = CIImage(color: CIColor(red: background.r, green: background.g, blue: background.b)).cropped(to: CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000))
        var composed: CIImage
        if let personMask {
            let f = CIFilter.blendWithMask(); f.inputImage = image; f.backgroundImage = bg; f.maskImage = personMask
            composed = f.outputImage ?? image
        } else { composed = image.composited(over: bg) }
        // crop (top-left pixels) -> CI rect (bottom-left), outside the photo it is the background colour
        let ci = CGRect(x: e.minX + crop.rect.minX, y: e.minY + e.height - crop.rect.maxY, width: crop.rect.width, height: crop.rect.height)
        let cropped = composed.cropped(to: ci).transformed(by: CGAffineTransform(translationX: -ci.minX, y: -ci.minY))
        let s = CGFloat(pw) / ci.width
        return cropped.transformed(by: CGAffineTransform(scaleX: s, y: CGFloat(ph) / ci.height)).cropped(to: CGRect(x: 0, y: 0, width: pw, height: ph))
    }

    /// The checks, measured in the finished photo's own pixels.
    static func check(_ s: Subject, spec: IDSpec, image: CGSize) -> IDPhotoMath.Check? {
        guard let crop = IDPhotoMath.crop(face: s.face, eyeY: s.eyeY, spec: spec, image: image) else { return nil }
        let r = crop.rect
        func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - r.minX, y: p.y - r.minY) }
        let face = CGRect(x: s.face.minX - r.minX, y: s.face.minY - r.minY, width: s.face.width, height: s.face.height)
        return IDPhotoMath.check(face: face, eyeY: s.eyeY - Double(r.minY), leftEye: local(s.leftEye), rightEye: local(s.rightEye), photo: r.size, spec: spec)
    }

    /// Several copies on a sheet of paper (mm), as an image at `dpi`.
    static func printSheet(photo: CIImage, spec: IDSpec, paperMM: CGSize, dpi: Double = 300) -> CIImage? {
        let slots = IDPhotoMath.sheet(paperMM: paperMM, photoMM: CGSize(width: spec.widthMM, height: spec.heightMM))
        guard !slots.isEmpty else { return nil }
        let k = dpi / 25.4
        let w = paperMM.width * k, h = paperMM.height * k
        var out = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        let pe = photo.extent
        for s in slots {
            let r = CGRect(x: s.minX * k, y: h - s.maxY * k, width: s.width * k, height: s.height * k)
            let placed = photo.transformed(by: CGAffineTransform(translationX: -pe.minX, y: -pe.minY)).transformed(by: CGAffineTransform(scaleX: r.width / pe.width, y: r.height / pe.height)).transformed(by: CGAffineTransform(translationX: r.minX, y: r.minY))
            out = placed.composited(over: out)
        }
        return out.cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    }
}

@Observable @MainActor
final class IDPhotoModel {
    private(set) var source: CIImage?
    private(set) var subject: IDPhotoRenderer.Subject?
    private var mask: CIImage?
    var specs: [IDSpec] = []
    var spec: IDSpec?
    var background = RGBA(r: 1, g: 1, b: 1, a: 1)
    private(set) var noFace = false
    private(set) var result: CIImage?
    private(set) var check: IDPhotoMath.Check?
    private(set) var saved = false

    init() {
        if let url = Bundle.main.url(forResource: "id-specs", withExtension: "json"), let d = try? Data(contentsOf: url), let all = try? IDSpec.load(d) { specs = all; spec = all.first; if let s = all.first { background = RGBA(r: s.background[0], g: s.background[1], b: s.background[2], a: 1) } }
    }

    func load(_ data: Data) {
        guard let img = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return }
        source = img; saved = false
        let proxy = Renderer.proxy(img, maxDimension: 2400)
        source = proxy
        let faces = (try? Renderer.services.faceLandmarker?.faces(in: proxy)) ?? []
        subject = faces.max { $0.box.width * $0.box.height < $1.box.width * $1.box.height }.flatMap { IDPhotoRenderer.subject(from: $0, imageSize: proxy.extent.size) }
        noFace = subject == nil
        mask = (try? Renderer.services.subjectMasker?.subjectMask(for: proxy)) ?? nil
        refresh()
    }

    func choose(_ s: IDSpec, keepBackground: Bool = false) {
        spec = s
        if !keepBackground { background = RGBA(r: s.background[0], g: s.background[1], b: s.background[2], a: 1) }
        refresh()
    }

    func setBackground(_ c: RGBA) { background = c; refresh() }

    private func refresh() {
        guard let source, let subject, let spec else { result = nil; check = nil; return }
        result = IDPhotoRenderer.render(source, subject: subject, spec: spec, background: background, personMask: mask)
        check = IDPhotoRenderer.check(subject, spec: spec, image: source.extent.size)
    }

    func save(sheet paper: CGSize? = nil) async -> Bool {
        guard let result, let spec else { return false }
        let img: CIImage? = paper.flatMap { IDPhotoRenderer.printSheet(photo: result, spec: spec, paperMM: $0) } ?? result
        guard let img, let space = CGColorSpace(name: CGColorSpace.sRGB), let jpeg = CIContext().jpegRepresentation(of: img, colorSpace: space) else { return false }
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpeg, options: nil) }; saved = true; return true } catch { return false }
    }
}
