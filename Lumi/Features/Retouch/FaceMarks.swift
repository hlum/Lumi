import CoreGraphics
import SwiftUI

/// The part of the face a slider is working on; the preview outlines it while the slider moves.
enum FaceMark: Hashable {
    case face, skin, jaw, chin, faceWidth, lift, eyes, brows, nose, mouth, lips, teeth, cheeks, blush, contour, highlight, underEye
    case hair            // drawn from the hair mask, not from landmarks
}

/// An outline in image-normalized coordinates, origin top-left.
enum MarkShape: Equatable {
    case line([CGPoint], closed: Bool)
    case ellipse(center: CGPoint, rx: CGFloat, ry: CGFloat)
}

enum FaceMarks {
    /// Outlines for `mark` on one face. `aspect` is image width / height, needed to turn the makeup spots (sized by width) into ellipses.
    static func shapes(_ mark: FaceMark, face: FaceInfo, aspect: CGFloat) -> [MarkShape] {
        func pts(_ r: String) -> [CGPoint] { FaceReshape.points(face, r) }
        func line(_ p: [CGPoint], closed: Bool = false) -> [MarkShape] { p.count >= 2 ? [.line(p, closed: closed)] : [] }
        func grown(_ p: [CGPoint], _ k: CGFloat) -> [CGPoint] {
            guard let c = FaceReshape.center(p) else { return p }
            return p.map { CGPoint(x: c.x + ($0.x - c.x) * k, y: c.y + ($0.y - c.y) * k) }
        }
        func spot(_ s: MakeupRenderer.Spot) -> MarkShape { .ellipse(center: s.center, rx: CGFloat(s.radius), ry: CGFloat(s.radius * s.squash) * aspect) }
        let contour = pts("faceContour")
        switch mark {
        case .hair: return []
        case .face:
            let b = MakeupRenderer.faceBox(face)
            return [.line([CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)], closed: true)]
        case .skin:
            let brows = pts("leftEyebrow") + pts("rightEyebrow")
            guard contour.count >= 3, let top = brows.map(\.y).min() else { return line(contour) }
            let lift = MakeupRenderer.faceBox(face).height * 0.12
            return line(contour + [CGPoint(x: contour.last!.x, y: top - lift), CGPoint(x: contour.first!.x, y: top - lift)], closed: true)
        case .jaw:
            guard let lo = contour.map(\.y).max(), let hi = contour.map(\.y).min() else { return [] }
            return line(contour.filter { $0.y - hi > (lo - hi) * 0.35 })
        case .chin:
            guard contour.count >= 5, let i = contour.indices.max(by: { contour[$0].y < contour[$1].y }) else { return [] }
            return line(Array(contour[max(0, i - 2)...min(contour.count - 1, i + 2)]))
        case .faceWidth: return line(contour)
        case .lift:
            guard let lo = contour.map(\.y).max(), let hi = contour.map(\.y).min() else { return [] }
            return line(contour.filter { $0.y - hi > (lo - hi) * 0.45 }) + MakeupRenderer.blushSpots(face, style: .round).map(spot)
        case .eyes: return line(grown(pts("leftEye"), 1.25), closed: true) + line(grown(pts("rightEye"), 1.25), closed: true)
        case .brows: return line(pts("leftEyebrow")) + line(pts("rightEyebrow"))
        case .nose: return line(grown(pts("nose"), 1.1))
        case .mouth, .lips: return line(pts("outerLips"), closed: true)
        case .teeth: return line(pts("innerLips"), closed: true)
        case .cheeks, .blush: return MakeupRenderer.blushSpots(face, style: .round).map(spot)
        case .contour: return MakeupRenderer.contourSpots(face).map(spot)
        case .highlight: return MakeupRenderer.highlightSpots(face).map(spot)
        case .underEye:
            return ["leftEye", "rightEye"].compactMap { r -> MarkShape? in
                let p = pts(r)
                guard let c = FaceReshape.center(p), FaceReshape.width(p) > 0 else { return nil }
                let w = FaceReshape.width(p)
                return .ellipse(center: CGPoint(x: c.x, y: c.y + w * 0.45 * aspect), rx: w * 0.7, ry: w * 0.28 * aspect)
            }
        }
    }
}

/// Draws the active mark for every detected face over the preview.
struct FaceMarksOverlay: View {
    var mark: FaceMark?
    var faces: [FaceInfo]
    var imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let map = FitMapping(view: geo.size, image: imageSize)
            let d = map.displayed
            let aspect = imageSize.width / max(imageSize.height, 1)
            ZStack {
                if let mark {
                    ForEach(Array(faces.enumerated()), id: \.offset) { _, face in
                        ForEach(Array(FaceMarks.shapes(mark, face: face, aspect: aspect).enumerated()), id: \.offset) { _, shape in
                            path(shape, in: d).stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .shadow(color: LumiColor.accent, radius: 3)
                            path(shape, in: d).stroke(LumiColor.accent, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, dash: [1, 5]))
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: mark)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func path(_ shape: MarkShape, in d: CGRect) -> Path {
        func v(_ p: CGPoint) -> CGPoint { CGPoint(x: d.minX + p.x * d.width, y: d.minY + p.y * d.height) }
        switch shape {
        case .line(let p, let closed):
            var path = Path()
            guard let first = p.first else { return path }
            path.move(to: v(first)); for q in p.dropFirst() { path.addLine(to: v(q)) }
            if closed { path.closeSubpath() }
            return path
        case .ellipse(let c, let rx, let ry):
            let o = v(c)
            return Path(ellipseIn: CGRect(x: o.x - rx * d.width, y: o.y - ry * d.height, width: rx * 2 * d.width, height: ry * 2 * d.height))
        }
    }
}
