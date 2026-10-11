import AVFoundation
import CoreImage

/// One time slice of the composition: either a single clip or a transition between two.
final class LumiInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    struct Layer { var trackID: CMPersistentTrackID; var look: EditDocument; var layout: ClipOps.FrameLayout }

    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let from: Layer
    let to: Layer?
    let transition: TransitionKind
    let renderSize: CGSize

    init(timeRange: CMTimeRange, from: Layer, to: Layer?, transition: TransitionKind, renderSize: CGSize) {
        self.timeRange = timeRange; self.from = from; self.to = to; self.transition = transition; self.renderSize = renderSize
        requiredSourceTrackIDs = ([from.trackID] + (to.map { [$0.trackID] } ?? [])).map { NSNumber(value: $0) }
    }
}

/// Applies each clip's look and layout, and blends transitions, with the same Core Image code the photo editor uses.
final class LumiCompositor: NSObject, AVVideoCompositing {
    private let context = CIContext()
    private let queue = DispatchQueue(label: "lumi.compositor")

    let sourcePixelBufferAttributes: [String: any Sendable]? = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        queue.async {
            guard let inst = request.videoCompositionInstruction as? LumiInstruction, let out = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "Lumi", code: 1)); return
            }
            func picture(_ l: LumiInstruction.Layer) -> CIImage? {
                guard let pb = request.sourceFrame(byTrackID: l.trackID) else { return nil }
                let styled = Renderer.render(CIImage(cvPixelBuffer: pb), document: l.look)
                return ClipOps.layout(styled, l.layout, canvas: inst.renderSize)
            }
            guard let a = picture(inst.from) else { request.finish(with: NSError(domain: "Lumi", code: 2)); return }
            var frame = a
            if let toLayer = inst.to, let b = picture(toLayer) {
                let t = Transitions.progress(at: request.compositionTime.seconds, start: inst.timeRange.start.seconds, duration: inst.timeRange.duration.seconds)
                frame = Transitions.frame(inst.transition, from: a, to: b, progress: t)
            }
            self.context.render(frame, to: out)
            request.finish(withComposedVideoFrame: out)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}
}
