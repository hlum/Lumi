import CoreImage
import Testing
import UIKit
@testable import Lumi

/// Renders each body slider on real photos copied into the app's Documents (not part of normal runs), with the joints and stroke centres drawn on.
@Suite(.serialized)
struct BodySliderDiagnosticsTests {
    static let docs = URL(fileURLWithPath: NSHomeDirectory() + "/Documents")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: BodySliderDiagnosticsTests.docs.appendingPathComponent("body3.jpg").path))) func renderEverySlider() throws {
        let ctx = CIContext()
        var report = ""
        let log = Self.docs.appendingPathComponent("body_progress.txt")
        func note(_ t: String) { report += t + "\n"; try? report.write(to: log, atomically: true, encoding: .utf8) }
        let t0 = Date()
        for name in ["body2", "body3"] {
            guard let photo = CIImage(contentsOf: Self.docs.appendingPathComponent(name + ".jpg")) else { continue }
            let proxy = Renderer.proxy(photo, maxDimension: 1000)
            note("\(name): start \(Date().timeIntervalSince(t0))")
            let poses = (try? Renderer.services.bodyFinder?.poses(in: proxy)) ?? []
            note("poses done \(Date().timeIntervalSince(t0))")
            let mask = try? Renderer.services.subjectMasker?.subjectMask(for: proxy)
            note("mask done \(Date().timeIntervalSince(t0))")
            report += "\(name): \(poses.count) poses, mask \(mask != nil)\n"
            for p in poses { for (k, v) in p.sorted(by: { $0.key < $1.key }) { report += "  \(k) \(String(format: "%.3f %.3f", v.x, v.y))\n" } }
            for key in BodyReshapeParams.Key.allCases {
                for protect in [false] {
                    var b = BodyRetouch(); b.params[keyPath: key.path] = 1; b.protectBackground = protect
                    let out = BodyRetouchRender.apply(b, to: proxy, poses: poses, personMask: mask, inpainter: protect ? LazyInpainter() : nil)
                    let strokes = BodyReshape.strokes(poses: poses, params: b.params)
                    guard let cg = ctx.createCGImage(out, from: out.extent) else { continue }
                    let size = out.extent.size
                    let img = UIGraphicsImageRenderer(size: size).image { r in
                        UIImage(cgImage: cg).draw(at: .zero)
                        let g = r.cgContext
                        for p in poses { for (_, v) in BodyReshape.joints(p) { g.setFillColor(UIColor.red.cgColor); g.fillEllipse(in: CGRect(x: v.x * size.width - 5, y: v.y * size.height - 5, width: 10, height: 10)) } }
                        for s in strokes {
                            let c = CGPoint(x: CGFloat(s.x) * size.width, y: CGFloat(s.y) * size.height)
                            g.setStrokeColor(UIColor.yellow.cgColor); g.setLineWidth(3)
                            g.move(to: c); g.addLine(to: CGPoint(x: c.x + CGFloat(s.dirX) * size.width * 3, y: c.y + CGFloat(s.dirY) * size.height * 3)); g.strokePath()
                            g.setStrokeColor(UIColor.cyan.withAlphaComponent(0.6).cgColor); g.setLineWidth(1)
                            g.strokeEllipse(in: CGRect(x: c.x - CGFloat(s.radius) * size.width, y: c.y - CGFloat(s.radius) * size.width, width: CGFloat(s.radius) * size.width * 2, height: CGFloat(s.radius) * size.width * 2))
                        }
                    }
                    note("\(key.rawValue) \(Date().timeIntervalSince(t0))")
                    try img.jpegData(compressionQuality: 0.8)?.write(to: Self.docs.appendingPathComponent("bd_\(name)_\(key.rawValue)_\(protect ? "p" : "n").jpg"))
                }
            }
            if let cg = ctx.createCGImage(proxy, from: proxy.extent) { try UIImage(cgImage: cg).jpegData(compressionQuality: 0.8)?.write(to: Self.docs.appendingPathComponent("bd_\(name)_base.jpg")) }
        }
        try report.write(to: Self.docs.appendingPathComponent("body_diag.txt"), atomically: true, encoding: .utf8)
    }
}
