import CoreImage
import Testing
import UIKit
@testable import Lumi

/// Phase Q0: renders every face, makeup and body control on the bench photos (Documents/bench, pushed by scripts/bench.sh)
/// and writes labelled contact sheets to Documents/bench_out. Skipped when the bench is not on the device.
@Suite(.serialized)
struct QualityBenchTests {
    static let docs = URL(fileURLWithPath: NSHomeDirectory() + "/Documents")
    static let bench = docs.appendingPathComponent("bench"), out = docs.appendingPathComponent("bench_out")
    /// The bench runs only when armed by `scripts/bench.sh push` (it is slow and heavy; `pull` disarms it).
    static var armed: Bool { (try? String(contentsOf: bench.appendingPathComponent("RUN"), encoding: .utf8))?.hasPrefix("1") == true }
    static var photos: [URL] { !armed ? [] : ((try? FileManager.default.contentsOfDirectory(at: bench, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "jpg" }.sorted { $0.path < $1.path } }
    static let ctx = CIContext()

    struct Tile { var label: String; var image: CIImage; var marks: (CGContext, CGSize) -> Void = { _, _ in } }

    /// Lays tiles out in a grid, each scaled to `height`, label on top.
    static func sheet(_ tiles: [Tile], height: CGFloat = 420, columns: Int = 5) -> UIImage {
        let aspect = tiles.first.map { $0.image.extent.width / max($0.image.extent.height, 1) } ?? 1
        let w = height * aspect, rows = (tiles.count + columns - 1) / columns, label: CGFloat = 26
        return UIGraphicsImageRenderer(size: CGSize(width: w * CGFloat(min(columns, tiles.count)), height: (height + label) * CGFloat(rows))).image { r in
            UIColor.white.setFill(); r.fill(r.format.bounds)
            for (i, t) in tiles.enumerated() {
                let origin = CGPoint(x: CGFloat(i % columns) * w, y: CGFloat(i / columns) * (height + label))
                (t.label as NSString).draw(at: CGPoint(x: origin.x + 6, y: origin.y + 3), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.black])
                guard let cg = ctx.createCGImage(t.image, from: t.image.extent) else { continue }
                let rect = CGRect(x: origin.x, y: origin.y + label, width: w, height: height)
                UIImage(cgImage: cg).draw(in: rect)
                let g = r.cgContext
                g.saveGState(); g.translateBy(x: rect.minX, y: rect.minY); g.clip(to: CGRect(origin: .zero, size: rect.size))
                t.marks(g, rect.size); g.restoreGState()
            }
        }
    }

    static func write(_ img: UIImage, _ name: String) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try img.jpegData(compressionQuality: 0.85)?.write(to: out.appendingPathComponent(name + ".jpg"))
    }

    static func render(_ proxy: CIImage, _ edit: (inout EditDocument) -> Void) -> CIImage {
        var d = EditDocument(); edit(&d); return Renderer.render(proxy, document: d)
    }

    /// Image-normalized (y-down) crop around a set of points, grown by `pad`.
    static func crop(_ img: CIImage, around pts: [CGPoint], pad: CGFloat) -> CIImage {
        guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(), let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return img }
        let e = img.extent, side = max(x1 - x0, (y1 - y0) * e.height / e.width) * (1 + pad)
        let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2
        let r = CGRect(x: e.minX + (cx - side / 2) * e.width, y: e.minY + (1 - cy - side * e.width / e.height / 2) * e.height, width: side * e.width, height: side * e.width).intersection(e)
        return img.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
    }

    @Test(.enabled(if: !QualityBenchTests.photos.filter { $0.lastPathComponent.hasPrefix("face_") }.isEmpty)) func faceAndMakeupSheets() throws {
        for url in Self.photos where url.lastPathComponent.hasPrefix("face_") {
            let name = url.deletingPathExtension().lastPathComponent
            guard let photo = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { continue }
            let proxy = Renderer.proxy(photo, maxDimension: 900)
            let faces = (try? Renderer.services.faceLandmarker?.faces(in: proxy)) ?? []
            let marks: (CGContext, CGSize) -> Void = { g, s in
                for f in faces { for (_, pts) in f.landmarks {
                    for p in pts { let q = CGPoint(x: (f.box.minX + p.x * f.box.width) * s.width, y: (1 - (f.box.minY + p.y * f.box.height)) * s.height)
                        g.setFillColor(UIColor.green.cgColor); g.fillEllipse(in: CGRect(x: q.x - 1.5, y: q.y - 1.5, width: 3, height: 3)) }
                } }
            }
            // face shape
            let sliders: [(String, WritableKeyPath<FaceRetouch, Double>, [Double])] = [
                ("chin", \.reshape.chinLength, [1, -1]), ("jaw", \.reshape.jawSlim, [1, -1]), ("V shape", \.shape.vShape, [1, -1]), ("width", \.reshape.faceWidth, [1, -1]),
                ("cheekbones", \.shape.cheekbones, [1]), ("cheek vol", \.reshape.cheekVolume, [1]), ("eyes", \.reshape.eyeSize, [1, -1]), ("nose", \.reshape.noseSlim, [1, -1]),
                ("mouth", \.reshape.mouthSize, [1, -1]), ("lift", \.reshape.lift, [1]), ("forehead", \.shape.forehead, [1]),
            ]
            var tiles = [Tile(label: "\(name) — \(faces.count) face(s)", image: proxy, marks: marks)]
            for (label, path, values) in sliders { for v in values {
                tiles.append(Tile(label: "\(label) \(v > 0 ? "+" : "")\(Int(v * 100))", image: Self.render(proxy) { var f = $0.face; f[keyPath: path] = v; $0.face = f }))
            } }
            try Self.write(Self.sheet(tiles), "\(name)_face")

            // makeup: whole-face looks plus lip close-ups
            guard let face = faces.first else { continue }
            let lips = FaceReshape.points(face, "outerLips"), eye = FaceReshape.points(face, "leftEye") + FaceReshape.points(face, "leftEyebrow")
            func look(_ m: (inout MakeupParams) -> Void, eyes: ((inout EyeMakeup) -> Void)? = nil) -> CIImage {
                Self.render(proxy) { d in var f = d.face; m(&f.makeup); if let eyes { eyes(&f.eyes) }; d.face = f }
            }
            let red = look { $0.lipOpacity = 1; $0.lipColor = RGBA(r: 0.75, g: 0.05, b: 0.12, a: 1); $0.lipFinish = .matte }
            let pink = look { $0.lipOpacity = 0.9; $0.lipColor = RGBA(r: 0.95, g: 0.45, b: 0.6, a: 1); $0.lipFinish = .gloss }
            let nude = look { $0.lipOpacity = 0.9; $0.lipColor = RGBA(r: 0.75, g: 0.5, b: 0.42, a: 1); $0.lipFinish = .satin }
            let blush = look { $0.blushOpacity = 1 }
            let sculpt = look { $0.contour = 1; $0.highlight = 1 }
            let base = look { $0.foundation = 1 }
            let eyes = look({ _ in }, eyes: { $0.setBoth { $0.shadow = 1; $0.liner = 1 }; $0.browOpacity = 0.6 })
            let glam = look({ $0.lipOpacity = 1; $0.lipColor = RGBA(r: 0.75, g: 0.05, b: 0.12, a: 1); $0.blushOpacity = 0.7; $0.contour = 0.6; $0.highlight = 0.6; $0.foundation = 0.5 }, eyes: { $0.setBoth { $0.shadow = 0.8; $0.liner = 0.8 } })
            var mt = [Tile(label: "\(name) makeup — none", image: proxy), Tile(label: "red matte", image: red), Tile(label: "pink gloss", image: pink), Tile(label: "nude satin", image: nude),
                      Tile(label: "blush", image: blush), Tile(label: "contour+highlight", image: sculpt), Tile(label: "foundation", image: base), Tile(label: "shadow+liner", image: eyes), Tile(label: "glam", image: glam)]
            try Self.write(Self.sheet(mt), "\(name)_makeup")
            mt = [Tile(label: "lips none", image: Self.crop(proxy, around: lips, pad: 0.6)), Tile(label: "red matte", image: Self.crop(red, around: lips, pad: 0.6)),
                  Tile(label: "pink gloss", image: Self.crop(pink, around: lips, pad: 0.6)), Tile(label: "nude satin", image: Self.crop(nude, around: lips, pad: 0.6)),
                  Tile(label: "eye none", image: Self.crop(proxy, around: eye, pad: 0.5)), Tile(label: "shadow+liner", image: Self.crop(eyes, around: eye, pad: 0.5))]
            try Self.write(Self.sheet(mt, height: 360, columns: 6), "\(name)_closeup")
        }
    }

    @Test(.enabled(if: !QualityBenchTests.photos.filter { $0.lastPathComponent.hasPrefix("body_") }.isEmpty)) func bodySheets() throws {
        for url in Self.photos where url.lastPathComponent.hasPrefix("body_") {
            let name = url.deletingPathExtension().lastPathComponent
            guard let photo = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { continue }
            let proxy = Renderer.proxy(photo, maxDimension: 1000)
            let poses = (try? Renderer.services.bodyFinder?.poses(in: proxy)) ?? []
            let mask = try? Renderer.services.subjectMasker?.subjectMask(for: proxy)
            let joints: (CGContext, CGSize) -> Void = { g, s in
                for p in poses { for (_, v) in BodyReshape.joints(p) { g.setFillColor(UIColor.red.cgColor); g.fillEllipse(in: CGRect(x: v.x * s.width - 4, y: v.y * s.height - 4, width: 8, height: 8)) } }
            }
            var tiles = [Tile(label: "\(name) — \(poses.count) pose(s)", image: proxy, marks: joints)]
            for key in BodyReshapeParams.Key.allCases {
                var b = BodyRetouch(); b.params[keyPath: key.path] = 1; b.protectBackground = false
                tiles.append(Tile(label: "\(key.rawValue) +100", image: BodyRetouchRender.apply(b, to: proxy, poses: poses, personMask: mask, inpainter: nil)))
            }
            // background protection with the built-in fill (the 2 GB diffusion model is too slow for a bench pass)
            var b = BodyRetouch(); b.params.waist = 1; b.params.hips = 1; b.protectBackground = true
            if let lama = try? LaMaInpainter() { tiles.append(Tile(label: "waist+hips, protected", image: BodyRetouchRender.apply(b, to: proxy, poses: poses, personMask: mask, inpainter: lama))) }
            try Self.write(Self.sheet(tiles, height: 520, columns: 6), "\(name)_body")
        }
    }

    @Test(.enabled(if: !QualityBenchTests.photos.filter { $0.lastPathComponent.hasPrefix("face_") }.isEmpty)) func faceParsingSheet() throws {
        let palette: [FacePart: UIColor] = [.skin: .orange, .leftBrow: .brown, .rightBrow: .brown, .leftEye: .cyan, .rightEye: .cyan, .glasses: .purple, .nose: .yellow,
                                            .mouth: .white, .upperLip: .red, .lowerLip: .magenta, .hair: .blue, .leftEar: .green, .rightEar: .green, .neck: .gray, .hat: .black]
        var tiles: [Tile] = []
        for url in Self.photos where url.lastPathComponent.hasPrefix("face_") {
            guard let photo = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { continue }
            let proxy = Renderer.proxy(photo, maxDimension: 900)
            guard let box = ((try? Renderer.services.faceFinder?.faceBoxes(in: proxy)) ?? []).first else { continue }
            let parse = try FaceParser().parse(proxy, faceBox: box)
            var over = proxy
            for (part, color) in palette {
                let m = parse.mask([part], extent: proxy.extent, soften: 0)
                let tint = CIImage(color: CIColor(color: color.withAlphaComponent(0.55))).cropped(to: proxy.extent)
                over = tint.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: over, kCIInputMaskImageKey: m]).cropped(to: proxy.extent)
            }
            let label = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "face_", with: "") + String(format: " lips %.3f teeth %.3f", parse.fraction(.upperLip) + parse.fraction(.lowerLip), parse.fraction(.mouth))
            tiles.append(Tile(label: label, image: over))
        }
        try Self.write(Self.sheet(tiles, height: 420, columns: 5), "parsing")
    }

    @Test(.enabled(if: QualityBenchTests.armed)) func eyeShadowMask() throws {
        let photo = try #require(CIImage(contentsOf: Self.bench.appendingPathComponent("face_light_woman.jpg"), options: [.applyOrientationProperty: true]))
        let proxy = Renderer.proxy(photo, maxDimension: 900)
        let face = try #require(try Renderer.services.faceLandmarker?.faces(in: proxy).first)
        let eye = FaceReshape.points(face, "leftEye")
        let mask = try #require(EyeMakeupRenderer.shadowMask(eye, size: proxy.extent.size))
        try Self.write(Self.sheet([Tile(label: "shadow mask", image: Self.crop(mask, around: eye, pad: 1.5))], height: 360, columns: 1), "eyeshadow_mask")
    }
}
