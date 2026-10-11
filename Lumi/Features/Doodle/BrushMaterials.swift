import CoreGraphics
import CoreImage
import Foundation
import UIKit

struct DoodleStroke: Codable, Equatable {
    enum Brush: String, Codable, CaseIterable { case solid, neon, dashed, dotted, marker, stars }
    var brush = Brush.solid
    var points: [CGPoint]           // normalized, y-down
    var color = RGBA.white
    var size = 0.015                // fraction of the long side
    var opacity = 1.0
}

enum Doodle {
    /// Smart line: if the stroke is nearly straight, replace it with its endpoints.
    static func snappedToLine(_ pts: [CGPoint], tolerance: Double = 0.02) -> [CGPoint] {
        guard pts.count > 2, let a = pts.first, let b = pts.last else { return pts }
        let len = hypot(b.x - a.x, b.y - a.y)
        guard len > 0.02 else { return pts }
        var maxDev = 0.0
        for p in pts {
            let cross: Double = (b.y - a.y) * p.x - (b.x - a.x) * p.y + b.x * a.y - b.y * a.x
            maxDev = max(maxDev, abs(cross) / len)
        }
        return maxDev <= tolerance ? [a, b] : pts
    }

    /// Draws strokes over `image`. Sizes are relative so preview and export match.
    /// Marker runs are blended with multiply (so what's underneath shows through); everything else is normal ink.
    static func render(_ strokes: [DoodleStroke], over image: CIImage) -> CIImage {
        guard !strokes.isEmpty else { return image }
        var out = image
        var run: [DoodleStroke] = []
        func flush() {
            guard let first = run.first, let layer = layer(run, matching: image) else { run = []; return }
            let mode = first.brush == .marker ? "CIMultiplyBlendMode" : "CISourceOverCompositing"
            out = layer.applyingFilter(mode, parameters: [kCIInputBackgroundImageKey: out]).cropped(to: image.extent)
            run = []
        }
        for s in strokes {
            if let f = run.first, (f.brush == .marker) != (s.brush == .marker) { flush() }
            run.append(s)
        }
        flush()
        return out
    }

    private static func layer(_ strokes: [DoodleStroke], matching image: CIImage) -> CIImage? {
        let e = image.extent, w = Int(e.width), h = Int(e.height)
        guard w > 0, h > 0, w * h < 120_000_000,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)                  // y-down like the points
        let long = CGFloat(max(w, h))
        for s in strokes where !s.points.isEmpty { draw(s, in: ctx, size: CGSize(width: w, height: h), long: long) }
        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg).transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY))
    }

    private static func draw(_ s: DoodleStroke, in ctx: CGContext, size: CGSize, long: CGFloat) {
        let pts = s.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let width = max(1, CGFloat(s.size) * long)
        let color = UIColor(red: s.color.r, green: s.color.g, blue: s.color.b, alpha: CGFloat(min(max(s.opacity, 0), 1)))
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        func path() { ctx.beginPath(); ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }; if pts.count == 1 { ctx.addLine(to: CGPoint(x: pts[0].x + 0.01, y: pts[0].y)) } }
        switch s.brush {
        case .solid:
            ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width); path(); ctx.strokePath()
        case .neon:
            ctx.setShadow(offset: .zero, blur: width * 1.5, color: color.cgColor)
            ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width); path(); ctx.strokePath()
            ctx.setShadow(offset: .zero, blur: 0); ctx.setStrokeColor(UIColor.white.withAlphaComponent(color.cgColor.alpha).cgColor); ctx.setLineWidth(width * 0.4); path(); ctx.strokePath()
        case .dashed:
            ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width); ctx.setLineCap(.butt); ctx.setLineDash(phase: 0, lengths: [width * 2.5, width * 1.5]); path(); ctx.strokePath()
        case .dotted:
            ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(width); ctx.setLineDash(phase: 0, lengths: [0.01, width * 2]); path(); ctx.strokePath()
        case .marker:
            ctx.setStrokeColor(color.withAlphaComponent(min(color.cgColor.alpha, 0.5)).cgColor); ctx.setLineCap(.square); ctx.setLineWidth(width * 2.5); path(); ctx.strokePath()
        case .stars:
            ctx.setFillColor(color.cgColor)
            var carry: CGFloat = 0
            let step = width * 2.2
            var prev = pts[0]
            for p in pts {
                var d = hypot(p.x - prev.x, p.y - prev.y)
                while carry + d >= step || prev == p && carry == 0 {
                    let t = d == 0 ? 0 : (step - carry) / d
                    let q = CGPoint(x: prev.x + (p.x - prev.x) * t, y: prev.y + (p.y - prev.y) * t)
                    star(ctx, q, width); prev = q; d = hypot(p.x - prev.x, p.y - prev.y); carry = 0
                    if d == 0 { break }
                }
                carry += d; prev = p
            }
        }
    }

    private static func star(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
        ctx.beginPath()
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5, rr = i % 2 == 0 ? r : r * 0.45
            let p = CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a))
            i == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
        }
        ctx.closePath(); ctx.fillPath()
    }
}
