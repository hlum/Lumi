import CoreGraphics
import CoreImage
import Vision

/// Follows one object through the video. Boxes are frame-normalized, y-down.
protocol ObjectTracking {
    /// First call gives the starting box; each later call returns where it went (nil = lost).
    mutating func next(frame: CIImage) -> CGRect?
}

struct VisionObjectTracker: ObjectTracking {
    private var observation: VNDetectedObjectObservation
    private let handler = VNSequenceRequestHandler()

    /// `start` is y-down normalized.
    init(start: CGRect) {
        observation = VNDetectedObjectObservation(boundingBox: CGRect(x: start.minX, y: 1 - start.maxY, width: start.width, height: start.height))
    }

    mutating func next(frame: CIImage) -> CGRect? {
        let req = VNTrackObjectRequest(detectedObjectObservation: observation)
        req.trackingLevel = .accurate
        guard (try? handler.perform([req], on: frame)) != nil, let r = req.results?.first as? VNDetectedObjectObservation, r.confidence > 0.3 else { return nil }
        observation = r
        return CGRect(x: r.boundingBox.minX, y: 1 - r.boundingBox.maxY, width: r.boundingBox.width, height: r.boundingBox.height)
    }
}

/// The recorded track: one box per frame, then smooth and look up by time. Lost frames hold the last known position.
struct ObjectTrack: Codable, Equatable {
    var fps: Double
    var boxes: [CGRect?]

    static func record(frames: [CIImage], start: CGRect, fps: Double, tracker: some ObjectTracking) -> ObjectTrack {
        var t = tracker
        return ObjectTrack(fps: fps, boxes: frames.map { t.next(frame: $0) })
    }

    /// Box at `time` (nearest frame), holding the previous known box through gaps; nil before the first detection.
    func box(at time: Double) -> CGRect? {
        guard fps > 0, !boxes.isEmpty else { return nil }
        let i = min(max(Int((time * fps).rounded()), 0), boxes.count - 1)
        for j in stride(from: i, through: 0, by: -1) { if let b = boxes[j] { return b } }
        return nil
    }

    /// Centers, lightly smoothed (moving average) so attached text doesn't jitter.
    func centers(radius: Int = 2) -> [CGPoint?] {
        let pts: [CGPoint?] = boxes.map { $0.map { CGPoint(x: $0.midX, y: $0.midY) } }
        return pts.indices.map { i in
            guard pts[i] != nil else { return nil }
            let near = pts[max(0, i - radius)...min(pts.count - 1, i + radius)].compactMap { $0 }
            return CGPoint(x: near.map(\.x).reduce(0, +) / CGFloat(near.count), y: near.map(\.y).reduce(0, +) / CGFloat(near.count))
        }
    }

    /// Pose center for an overlay attached to the object, keeping its `offset` from the tracked box center.
    func attachedCenter(at time: Double, offset: CGPoint = .zero) -> CGPoint? {
        box(at: time).map { CGPoint(x: $0.midX + offset.x, y: $0.midY + offset.y) }
    }
}

/// Person matting on video: segment each frame, then smooth over time so the edge doesn't flicker.
struct MatteSmoother {
    var weight = 0.5                      // share of the previous matte kept, 0...0.9
    private var previous: CIImage?

    mutating func smooth(_ matte: CIImage) -> CIImage {
        guard let p = previous, p.extent == matte.extent else { previous = matte; return matte }
        let w = CGFloat(min(max(weight, 0), 0.9))
        let mixed = matte.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1 - w, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1 - w, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 1 - w, w: 0)])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: p.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: w, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: w, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: w, w: 0)])]).cropped(to: matte.extent)
        previous = mixed
        return mixed
    }

    mutating func reset() { previous = nil }
}
