import CoreGraphics
import Foundation
import Vision

struct FaceInfo: Sendable, Equatable {
    var box: CGRect                  // normalized, origin bottom-left (Vision space)
    var landmarks: [String: [CGPoint]]
}

struct Analysis: Sendable, Equatable {
    var faces: [FaceInfo] = []
    var bodies: [[String: CGPoint]] = []
    var textBoxes: [CGRect] = []
    var personInstanceCount = 0
    var hasForegroundSubject = false
}

protocol ImageAnalyzing: Sendable {
    func analyze(_ image: CGImage) async throws -> Analysis
}

/// One call, all analyses. Vision requests run in a single handler pass.
struct VisionAnalyzer: ImageAnalyzing {
    func analyze(_ image: CGImage) async throws -> Analysis {
        try await Task.detached {
            let faces = VNDetectFaceLandmarksRequest()
            let pose = VNDetectHumanBodyPoseRequest()
            let text = VNRecognizeTextRequest()
            let people = VNGeneratePersonInstanceMaskRequest()
            let subject = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image)
            try handler.perform([faces, pose, text, people, subject])

            var a = Analysis()
            a.faces = (faces.results ?? []).map { f in
                var lm: [String: [CGPoint]] = [:]
                if let l = f.landmarks {
                    let regions: [(String, VNFaceLandmarkRegion2D?)] = [
                        ("leftEye", l.leftEye), ("rightEye", l.rightEye), ("nose", l.nose), ("outerLips", l.outerLips),
                        ("innerLips", l.innerLips), ("leftEyebrow", l.leftEyebrow), ("rightEyebrow", l.rightEyebrow), ("faceContour", l.faceContour),
                    ]
                    for (name, r) in regions { if let r { lm[name] = r.normalizedPoints } }
                }
                return FaceInfo(box: f.boundingBox, landmarks: lm)
            }
            a.bodies = (pose.results ?? []).map { o in
                var d: [String: CGPoint] = [:]
                for (k, p) in (try? o.recognizedPoints(.all)) ?? [:] where p.confidence > 0.1 { d[k.rawValue.rawValue] = p.location }
                return d
            }
            a.textBoxes = (text.results ?? []).map(\.boundingBox)
            a.personInstanceCount = people.results?.first?.allInstances.count ?? 0
            a.hasForegroundSubject = !(subject.results?.first?.allInstances.isEmpty ?? true)
            return a
        }.value
    }
}
