import CoreImage
import Foundation
import Observation

enum MaskScaling {
    /// Scales a stored mask to an image's pixel extent (masks are stored at their own, smaller size).
    static func scaled(_ m: MaskCanvas, to extent: CGRect) -> CIImage {
        let sx = extent.width / CGFloat(m.width), sy = extent.height / CGFloat(m.height)
        return m.ciImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy)).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0)]).cropped(to: extent)
    }
}

/// Maps between a view showing an image aspect-fit and the image's own coordinate space.
struct FitMapping: Equatable {
    let view: CGSize
    let image: CGSize

    var scale: CGFloat { min(view.width / max(image.width, 1), view.height / max(image.height, 1)) }
    var displayed: CGRect {
        let w = image.width * scale, h = image.height * scale
        return CGRect(x: (view.width - w) / 2, y: (view.height - h) / 2, width: w, height: h)
    }
    /// View point -> image point, top-left origin, nil when outside the picture.
    func toImage(_ p: CGPoint) -> CGPoint? {
        let d = displayed
        guard d.contains(p), scale > 0 else { return nil }
        return CGPoint(x: (p.x - d.minX) / scale, y: (p.y - d.minY) / scale)
    }
    /// Same, clamped to the picture edge instead of rejecting.
    func toImageClamped(_ p: CGPoint) -> CGPoint {
        let d = displayed
        return CGPoint(x: (min(max(p.x, d.minX), d.maxX) - d.minX) / max(scale, 1e-9), y: (min(max(p.y, d.minY), d.maxY) - d.minY) / max(scale, 1e-9))
    }
}

/// Draws a removal mask with a brush or box, then hands it to the document.
@Observable
final class RemoverModel {
    static let maskSide = 1024

    enum Mode { case brush, box }
    var mode = Mode.brush
    var brushSize = 0.04            // fraction of the image's long side
    private(set) var mask: MaskCanvas
    private let imageSize: CGSize
    private var last: CGPoint?
    private var boxStart: CGPoint?
    private(set) var strokesHistory: [MaskCanvas] = []

    init(imageSize: CGSize) {
        self.imageSize = imageSize
        let long = Double(max(imageSize.width, imageSize.height, 1))
        mask = MaskCanvas(width: max(1, Int((Double(imageSize.width) / long * Double(Self.maskSide)).rounded())),
                          height: max(1, Int((Double(imageSize.height) / long * Double(Self.maskSide)).rounded())))
    }

    var hasSelection: Bool { !mask.isEmpty }
    var canUndo: Bool { !strokesHistory.isEmpty }

    private func toMask(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / max(imageSize.width, 1) * CGFloat(mask.width), y: p.y / max(imageSize.height, 1) * CGFloat(mask.height))
    }

    func begin(at imagePoint: CGPoint) {
        strokesHistory.append(mask)
        let p = toMask(imagePoint)
        switch mode {
        case .brush: last = p; mask.stamp(x: p.x, y: p.y, radius: radius, hardness: 0.8, erase: false)
        case .box: boxStart = p
        }
    }

    func move(to imagePoint: CGPoint) {
        let p = toMask(imagePoint)
        switch mode {
        case .brush:
            guard let a = last else { return }
            mask.stroke(from: (a.x, a.y), to: (p.x, p.y), radius: radius, hardness: 0.8, erase: false); last = p
        case .box: break          // the box is committed on end; drag preview is the view's job
        }
    }

    func end(at imagePoint: CGPoint) {
        if mode == .box, let s = boxStart {
            let p = toMask(imagePoint)
            mask.fill(rect: CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y)))
        }
        last = nil; boxStart = nil
        if mask == strokesHistory.last { strokesHistory.removeLast() }       // a no-op gesture is not an undo step
    }

    func undoStroke() { if let m = strokesHistory.popLast() { mask = m } }
    func clear() { mask = MaskCanvas(width: mask.width, height: mask.height); strokesHistory = [] }

    private var radius: Double { brushSize * Double(max(mask.width, mask.height)) / 2 }

    /// The mask to commit, or nil when nothing is selected. Clears the selection.
    func take() -> MaskCanvas? {
        guard hasSelection else { return nil }
        let m = mask; clear(); return m
    }
}
