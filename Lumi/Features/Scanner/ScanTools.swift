import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

enum ScanFilter: String, CaseIterable, Codable { case original, enhance, grayscale, blackWhite }

enum ScanTools {
    static func apply(_ f: ScanFilter, to image: CIImage) -> CIImage {
        switch f {
        case .original: return image
        case .enhance:
            let c = CIFilter.colorControls(); c.inputImage = image; c.contrast = 1.25; c.brightness = 0.04; c.saturation = 1.1
            let s = CIFilter.sharpenLuminance(); s.inputImage = c.outputImage; s.sharpness = 0.6
            return (s.outputImage ?? image).cropped(to: image.extent)
        case .grayscale:
            let c = CIFilter.colorControls(); c.inputImage = image; c.saturation = 0; c.contrast = 1.15
            return c.outputImage ?? image
        case .blackWhite:
            let g = CIFilter.colorControls(); g.inputImage = image; g.saturation = 0
            let t = CIFilter.colorThreshold(); t.inputImage = g.outputImage; t.threshold = 0.55
            return (t.outputImage ?? image).cropped(to: image.extent)
        }
    }

    /// Flattens a skewed page given its corners (normalized, origin bottom-left, as Vision reports them).
    static func flatten(_ image: CIImage, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) -> CIImage {
        let e = image.extent
        func p(_ n: CGPoint) -> CIVector { CIVector(x: e.minX + n.x * e.width, y: e.minY + n.y * e.height) }
        let f = CIFilter.perspectiveCorrection()
        f.inputImage = image; f.topLeft = CGPoint(x: p(topLeft).x, y: p(topLeft).y); f.topRight = CGPoint(x: p(topRight).x, y: p(topRight).y)
        f.bottomLeft = CGPoint(x: p(bottomLeft).x, y: p(bottomLeft).y); f.bottomRight = CGPoint(x: p(bottomRight).x, y: p(bottomRight).y)
        return f.outputImage ?? image
    }

    /// Detects the most prominent page-like rectangle.
    static func detectPage(in image: CIImage) -> VNRectangleObservation? {
        let req = VNDetectRectanglesRequest()
        req.minimumAspectRatio = 0.3; req.maximumObservations = 1; req.minimumConfidence = 0.6; req.minimumSize = 0.2
        try? VNImageRequestHandler(ciImage: image).perform([req])
        return req.results?.first
    }

    /// Recognized text, top to bottom.
    static func recognizeText(in image: CIImage) throws -> [String] {
        let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.usesLanguageCorrection = true
        try VNImageRequestHandler(ciImage: image).perform([req])
        return (req.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }.compactMap { $0.topCandidates(1).first?.string }
    }

    /// One PDF page per image, each page the size of its image.
    static func pdf(_ images: [UIImage]) -> Data? {
        guard !images.isEmpty else { return nil }
        let first = CGRect(origin: .zero, size: images[0].size)
        let r = UIGraphicsPDFRenderer(bounds: first)
        return r.pdfData { ctx in
            for img in images {
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: img.size), pageInfo: [:])
                img.draw(in: CGRect(origin: .zero, size: img.size))
            }
        }
    }
}
