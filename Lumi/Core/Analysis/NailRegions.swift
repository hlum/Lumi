import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// One fingernail as an ellipse, image-normalized, y-down.
struct Nail: Equatable {
    var center: CGPoint
    var width: CGFloat          // across the finger
    var length: CGFloat         // along the finger
    var angle: CGFloat          // radians, direction from the joint to the tip
}

protocol HandFinding {
    /// Per hand, per finger: [DIP joint, tip] in image-normalized, y-down space.
    func fingertips(in image: CIImage) throws -> [[[CGPoint]]]
}

struct VisionHandFinder: HandFinding {
    func fingertips(in image: CIImage) throws -> [[[CGPoint]]] {
        let req = VNDetectHumanHandPoseRequest(); req.maximumHandCount = 4
        try VNImageRequestHandler(ciImage: image).perform([req])
        let pairs: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] =
            [(.thumbIP, .thumbTip), (.indexDIP, .indexTip), (.middleDIP, .middleTip), (.ringDIP, .ringTip), (.littleDIP, .littleTip)]
        return (req.results ?? []).map { hand in
            pairs.compactMap { a, b in
                guard let p = try? hand.recognizedPoint(a), let q = try? hand.recognizedPoint(b), p.confidence > 0.3, q.confidence > 0.3 else { return nil }
                return [CGPoint(x: p.location.x, y: 1 - p.location.y), CGPoint(x: q.location.x, y: 1 - q.location.y)]
            }
        }
    }
}

enum NailRegions {
    /// A nail sits at the end of the last finger segment: covers ~60% of it, a bit narrower than long.
    static func nails(from fingers: [[CGPoint]]) -> [Nail] {
        fingers.compactMap { f in
            guard f.count == 2 else { return nil }
            let dx = f[1].x - f[0].x, dy = f[1].y - f[0].y, len = (dx * dx + dy * dy).squareRoot()
            guard len > 0.002 else { return nil }
            let nailLen = len * 0.9
            let back = (len - nailLen) / 2 / len
            return Nail(center: CGPoint(x: f[1].x - dx * (0.5 * nailLen / len) - dx * back * 0, y: f[1].y - dy * (0.5 * nailLen / len)),
                        width: nailLen * 0.8, length: nailLen, angle: atan2(dy, dx))
        }
    }

    /// Nails for every hand found; an empty list (not an error) when none is.
    static func find(in image: CIImage, finder: HandFinding = VisionHandFinder()) -> [Nail] {
        ((try? finder.fingertips(in: image)) ?? []).flatMap { nails(from: $0) }
    }
}

enum NailRenderer {
    static func apply(_ nails: [Nail], color: CIColor, opacity: Double, to image: CIImage) -> CIImage {
        guard !nails.isEmpty, opacity > 0 else { return image }
        let e = image.extent
        var mask = CIImage(color: .black).cropped(to: e)
        let w = e.width, h = e.height
        for n in nails {
            let g = CIFilter.radialGradient()
            g.center = .zero; g.radius0 = 0.75; g.radius1 = 1; g.color0 = .white; g.color1 = .black   // unit disc, soft rim
            guard let disc = g.outputImage?.cropped(to: CGRect(x: -1, y: -1, width: 2, height: 2)) else { continue }
            // unit disc -> ellipse (length along the finger), rotated, placed (y-down -> CI y-up)
            let t = CGAffineTransform(translationX: e.minX + n.center.x * w, y: e.minY + (1 - n.center.y) * h)
                .rotated(by: -n.angle)
                .scaledBy(x: n.length * max(w, h) / 2, y: n.width * max(w, h) / 2)
            mask = disc.transformed(by: t).composited(over: mask).cropped(to: e)
        }
        let tint = CIImage(color: color).cropped(to: e)
        let f = CIFilter.blendWithMask()
        f.inputImage = tint; f.backgroundImage = image
        f.maskImage = mask.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: CGFloat(opacity), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: CGFloat(opacity), y: 0, z: 0, w: 0), "inputBVector": CIVector(x: CGFloat(opacity), y: 0, z: 0, w: 0)])
        return f.outputImage?.cropped(to: e) ?? image
    }
}

/// What the nails get painted with.
struct NailPaint: Codable, Equatable {
    enum Finish: String, Codable, CaseIterable { case cream, glossy, shimmer, french }
    var color = RGBA(r: 0.85, g: 0.2, b: 0.35, a: 1)
    var finish = Finish.glossy
    var opacity = 0.0                 // 0 = off
    var isIdentity: Bool { opacity <= 0 }
}

extension NailRenderer {
    /// Paints with a finish: cream is flat colour; glossy adds a light streak; shimmer adds sparkle; french paints only the tip white and leaves the rest sheer.
    static func paint(_ nails: [Nail], _ p: NailPaint, to image: CIImage) -> CIImage {
        guard !nails.isEmpty, !p.isIdentity else { return image }
        let color = CIColor(red: p.color.r, green: p.color.g, blue: p.color.b)
        switch p.finish {
        case .cream: return apply(nails, color: color, opacity: p.opacity, to: image)
        case .glossy:
            let base = apply(nails, color: color, opacity: p.opacity, to: image)
            // a thin bright streak along each nail, a little off center
            let streaks = nails.map { n -> Nail in var s = n; s.width = n.width * 0.18; s.length = n.length * 0.6; s.center = CGPoint(x: n.center.x - cos(n.angle + .pi / 2) * n.width * 0.22, y: n.center.y - sin(n.angle + .pi / 2) * n.width * 0.22); return s }
            return apply(streaks, color: CIColor(red: 1, green: 1, blue: 1), opacity: min(p.opacity * 0.55, 0.6), to: base)
        case .shimmer:
            let base = apply(nails, color: color, opacity: p.opacity, to: image)
            let e = image.extent
            let sparkle = (CIFilter(name: "CIRandomGenerator")?.outputImage ?? CIImage()).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 4])
                .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 3, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 3, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 3, w: 0), "inputBiasVector": CIVector(x: -2, y: -2, z: -2, w: 0)]).applyingFilter("CIColorClamp").cropped(to: e)
            let nailMask = apply(nails, color: .white, opacity: 1, to: CIImage(color: .black).cropped(to: e))
            let masked = sparkle.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: nailMask]).cropped(to: e)
            return masked.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: base]).cropped(to: e)
        case .french:
            // sheer pink base over the whole nail, white over its outer 35%
            let base = apply(nails, color: CIColor(red: 0.95, green: 0.75, blue: 0.75), opacity: p.opacity * 0.35, to: image)
            let tips = nails.map { n -> Nail in
                var t = n; t.length = n.length * 0.35; t.width = n.width * 0.95
                t.center = CGPoint(x: n.center.x + cos(n.angle) * n.length * 0.33, y: n.center.y + sin(n.angle) * n.length * 0.33)
                return t
            }
            return apply(tips, color: .white, opacity: p.opacity, to: base)
        }
    }
}
