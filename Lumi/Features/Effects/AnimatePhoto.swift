import CoreImage
import Foundation

/// Turns a still into motion: a slow Ken Burns move, or a 2.5D parallax where the person and the background drift apart.
struct AnimatePhoto: Codable, Equatable {
    enum Style: String, Codable, CaseIterable { case zoomIn, zoomOut, panLeft, panRight, parallax }
    var style = Style.zoomIn
    var duration = 3.0
    var fps = 30.0
    var intensity = 0.5               // 0...1

    var frameCount: Int { max(Int((duration * fps).rounded()), 1) }

    /// Camera at progress `p` (0...1): scale and a drift in frame fractions.
    func camera(at p: Double) -> (scale: Double, dx: Double, dy: Double) {
        let u = min(max(p, 0), 1), eased = u * u * (3 - 2 * u), k = min(max(intensity, 0), 1) * 0.2
        switch style {
        case .zoomIn: return (1 + k * eased, 0, 0)
        case .zoomOut: return (1 + k * (1 - eased), 0, 0)
        case .panLeft: return (1 + k, k * (0.5 - eased), 0)
        case .panRight: return (1 + k, k * (eased - 0.5), 0)
        case .parallax: return (1 + k * 0.5, k * 0.5 * sin(u * 2 * .pi), 0)
        }
    }

    /// One frame. For parallax, `personMask` (white = person) lets the person move more than the background.
    func frame(of image: CIImage, personMask: CIImage?, at p: Double) -> CIImage {
        let e = image.extent
        func moved(_ img: CIImage, scale: Double, dx: Double, dy: Double) -> CIImage {
            let t = CGAffineTransform(translationX: -e.midX, y: -e.midY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: e.midX + dx * e.width, y: e.midY + dy * e.height))
            return img.clampedToExtent().transformed(by: t).cropped(to: e)
        }
        let c = camera(at: p)
        guard style == .parallax, let personMask else { return moved(image, scale: c.scale, dx: c.dx, dy: c.dy) }
        let back = moved(image, scale: c.scale, dx: c.dx, dy: c.dy)
        let front = moved(image, scale: c.scale * 1.03, dx: c.dx * 2.2, dy: c.dy * 2.2)
        let m = moved(personMask, scale: c.scale * 1.03, dx: c.dx * 2.2, dy: c.dy * 2.2)
        let f = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: front, kCIInputBackgroundImageKey: back, kCIInputMaskImageKey: m])!
        return f.outputImage?.cropped(to: e) ?? back
    }

    func frames(of image: CIImage, personMask: CIImage?) -> [CIImage] {
        let n = frameCount
        return (0..<n).map { frame(of: image, personMask: personMask, at: n > 1 ? Double($0) / Double(n - 1) : 0) }
    }
}
