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
