import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Finds the foreground subject. Fakeable in tests.
protocol SubjectMasking {
    /// White = subject, same extent as `image`. Nil when no subject is found.
    func subjectMask(for image: CIImage) throws -> CIImage?
}

struct VisionSubjectMasker: SubjectMasking {
    func subjectMask(for image: CIImage) throws -> CIImage? {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([req])
        guard let obs = req.results?.first, !obs.allInstances.isEmpty else { return nil }
        let buf = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
        return CIImage(cvPixelBuffer: buf).cropped(to: image.extent)
    }
}

struct CutoutConfig: Codable, Equatable {
    enum Background: Codable, Equatable {
        case transparent
        case color(RGBA)
        case gradient(RGBA, RGBA)        // top, bottom
        case blur(Double)                // radius as a fraction of the long side
    }
    var background = Background.transparent
    var feather = 0.0                    // 0...1 edge softness
    var shift = 0.0                      // -1...1: negative grows the subject, positive shrinks it
    var invert = false                   // keep the background, drop the subject
}

enum CutoutOps {
    /// Edge refinement: shrink/grow, then soften. Radii scale with image size so preview and export match.
    static func refine(_ mask: CIImage, _ c: CutoutConfig) -> CIImage {
        let e = mask.extent
        let unit = Double(max(e.width, e.height)) * 0.01
        var m = mask
        if c.shift != 0 {
            let f = CIFilter(name: c.shift > 0 ? "CIMorphologyMinimum" : "CIMorphologyMaximum")!
            f.setValue(m.clampedToExtent(), forKey: kCIInputImageKey); f.setValue(abs(c.shift) * unit * 3, forKey: kCIInputRadiusKey)
            m = f.outputImage?.cropped(to: e) ?? m
        }
        if c.feather > 0 {
            m = m.clampedToExtent().applyingGaussianBlur(sigma: min(max(c.feather, 0), 1) * unit * 2).cropped(to: e)
        }
        if c.invert {
            m = m.applyingFilter("CIColorInvert").cropped(to: e)
        }
        return m
    }

    static func background(_ b: CutoutConfig.Background, for image: CIImage) -> CIImage {
        let e = image.extent
        func ci(_ c: RGBA) -> CIColor { CIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
        switch b {
        case .transparent: return CIImage(color: .clear).cropped(to: e)
        case .color(let c): return CIImage(color: ci(c)).cropped(to: e)
        case .gradient(let top, let bottom):
            let g = CIFilter.linearGradient()
            g.point0 = CGPoint(x: e.midX, y: e.maxY); g.point1 = CGPoint(x: e.midX, y: e.minY); g.color0 = ci(top); g.color1 = ci(bottom)
            return g.outputImage?.cropped(to: e) ?? CIImage(color: ci(top)).cropped(to: e)
        case .blur(let r):
            let radius = min(max(r, 0), 1) * Double(max(e.width, e.height)) * 0.05
            return image.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: e)
        }
    }

    static func apply(_ c: CutoutConfig, to image: CIImage, subjectMask: CIImage) -> CIImage {
        let m = refine(subjectMask, c)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image; blend.backgroundImage = background(c.background, for: image); blend.maskImage = m
        return blend.outputImage?.cropped(to: image.extent) ?? image
    }
}
