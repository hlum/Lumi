import CoreImage
import Vision

enum AutoStraighten {
    /// Angle in degrees to set as `CropSpec.angle` so the horizon becomes level, or nil when no confident horizon is found.
    static func angle(for image: CIImage, maxAngle: Double = 20) -> Double? {
        let req = VNDetectHorizonRequest()
        guard (try? VNImageRequestHandler(ciImage: image).perform([req])) != nil, let h = req.results?.first else { return nil }
        // Vision reports the rotation (radians) that levels the horizon, counter-clockwise positive; our angle is clockwise-positive.
        let degrees = -Double(h.angle) * 180 / .pi
        guard abs(degrees) <= maxAngle, abs(degrees) >= 0.2 else { return nil }
        return (degrees * 10).rounded() / 10
    }
}
