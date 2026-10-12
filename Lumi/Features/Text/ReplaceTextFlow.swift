import CoreImage
import UIKit
import Vision

/// One line of text found in a photo.
struct TextLine: Equatable, Identifiable {
    var id = UUID()
    var text: String
    var box: CGRect                   // normalized, origin bottom-left (Vision space)
}

protocol TextReading { func lines(in image: CIImage) throws -> [TextLine] }

struct VisionTextReader: TextReading {
    func lines(in image: CIImage) throws -> [TextLine] {
        let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.usesLanguageCorrection = true
        req.recognitionLanguages = ["en-US", "ja-JP"]
        try VNImageRequestHandler(ciImage: image).perform([req])
        return (req.results ?? []).compactMap { r in r.topCandidates(1).first.map { TextLine(text: $0.string, box: r.boundingBox) } }
            .sorted { $0.box.midY > $1.box.midY }
    }
}

/// Changes a piece of text in a photo: the old words are removed from the picture, new ones are set in the same colour and size.
enum ReplaceText {
    /// Background and text colour of a small crop (RGBA bytes): the most common colour is the background, the pixels far from it are the text.
    static func sampleColors(rgba: [UInt8]) -> (background: RGBA, text: RGBA)? {
        let n = rgba.count / 4
        guard n >= 4 else { return nil }
        var bins: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        for i in 0..<n {
            let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let e = bins[key] ?? (0, 0, 0, 0)
            bins[key] = (e.count + 1, e.r + r, e.g + g, e.b + b)
        }
        guard let top = bins.values.max(by: { $0.count < $1.count }) else { return nil }
        let bg = (Double(top.r) / Double(top.count), Double(top.g) / Double(top.count), Double(top.b) / Double(top.count))
        // text pixels: clearly different from the background; take their mean
        var sr = 0.0, sg = 0.0, sb = 0.0, c = 0.0
        for i in 0..<n {
            let r = Double(rgba[i * 4]), g = Double(rgba[i * 4 + 1]), b = Double(rgba[i * 4 + 2])
            if abs(r - bg.0) + abs(g - bg.1) + abs(b - bg.2) > 120 { sr += r; sg += g; sb += b; c += 1 }
        }
        let text: RGBA = c >= 2 ? RGBA(r: sr / c / 255, g: sg / c / 255, b: sb / c / 255, a: 1)
            : ((0.3 * bg.0 + 0.6 * bg.1 + 0.1 * bg.2) > 128 ? RGBA(r: 0.05, g: 0.05, b: 0.05, a: 1) : RGBA(r: 0.95, g: 0.95, b: 0.95, a: 1))
        return (RGBA(r: bg.0 / 255, g: bg.1 / 255, b: bg.2 / 255, a: 1), text)
    }

    /// Font size (fraction of the photo's height) that makes `string` about as wide as `boxWidthPx`, never taller than the line was.
    static func fontSize(for string: String, fontName: String, boxWidthPx: CGFloat, boxHeightPx: CGFloat, photoHeightPx: CGFloat) -> Double {
        guard photoHeightPx > 0, boxHeightPx > 0, !string.isEmpty else { return 0.04 }
        var pts = boxHeightPx * 0.82
        let font = UIFont(name: fontName, size: pts) ?? .boldSystemFont(ofSize: pts)
        let w = (string as NSString).size(withAttributes: [.font: font]).width
        if w > boxWidthPx * 1.05 { pts *= boxWidthPx * 1.05 / w }
        return Double(pts / photoHeightPx)
    }

    struct Plan { var mask: MaskCanvas; var layer: Layer }

    /// What to change in the document: the removal mask over the old line and the new text layer on top.
    static func plan(line: TextLine, newText: String, in image: CIImage, fontName: String = "HelveticaNeue-Bold") -> Plan? {
        let e = image.extent
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.width > 0, e.height > 0, !trimmed.isEmpty else { return nil }
        let box = line.box
        // colours from the crop
        let crop = CGRect(x: e.minX + box.minX * e.width, y: e.minY + box.minY * e.height, width: box.width * e.width, height: box.height * e.height).integral.intersection(e)
        var colors = (RGBA(r: 0.05, g: 0.05, b: 0.05, a: 1), RGBA(r: 0.05, g: 0.05, b: 0.05, a: 1))
        if crop.width >= 2, crop.height >= 2 {
            let w = min(Int(crop.width), 48), h = max(Int(CGFloat(w) * crop.height / crop.width), 2)
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let small = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)).transformed(by: CGAffineTransform(scaleX: CGFloat(w) / crop.width, y: CGFloat(h) / crop.height))
            CIContext().render(small, toBitmap: &px, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            if let s = sampleColors(rgba: px) { colors = (s.background, s.text) }
        }
        let size = fontSize(for: trimmed, fontName: fontName, boxWidthPx: box.width * e.width, boxHeightPx: box.height * e.height, photoHeightPx: e.height)
        var style = TextStyle(); style.fontName = fontName; style.size = size; style.color = colors.1
        var layer = Layer(content: .text(trimmed, style))
        layer.transform.center = CGPoint(x: box.midX, y: 1 - box.midY)           // y-down
        // removal mask: the line a little bigger, in a 1024-side canvas (top-left rows)
        let side = 1024.0, cw = Int(max(e.width, e.height) == e.width ? side : (side * e.width / e.height).rounded()), ch = Int(max(e.width, e.height) == e.width ? (side * e.height / e.width).rounded() : side)
        var m = MaskCanvas(width: max(cw, 1), height: max(ch, 1))
        let pad = 0.012
        m.fill(rect: CGRect(x: (box.minX - pad) * Double(cw), y: (1 - box.maxY - pad) * Double(ch), width: (box.width + 2 * pad) * Double(cw), height: (box.height + 2 * pad) * Double(ch)))
        return Plan(mask: m, layer: layer)
    }
}

/// Caption ideas for a photo, from what Vision sees in it. A language model can replace this later by conforming to the same protocol.
protocol CaptionSuggesting { func suggestions(for image: CIImage) async -> [String] }

struct SceneCaptionSuggester: CaptionSuggesting {
    func suggestions(for image: CIImage) async -> [String] {
        let labels = await Task.detached { () -> [String] in
            let req = VNClassifyImageRequest()
            try? VNImageRequestHandler(ciImage: image).perform([req])
            return (req.results ?? []).filter { $0.confidence > 0.25 }.prefix(3).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }.value
        return Self.captions(from: labels)
    }

    static func captions(from labels: [String]) -> [String] {
        guard let first = labels.first else { return ["Little moments", "Just as it was", "Saved for later"] }
        var out = ["\(first.capitalized) days", "Found some \(first)", "More \(first), please"]
        if let second = labels.dropFirst().first { out.append("\(first.capitalized) and \(second)") }
        return out
    }
}
