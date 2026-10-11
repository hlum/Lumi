import Vision
import CoreImage
import Foundation

/// Mosaic as a document operation: brushed/boxed masks plus optional automatic face cover.
struct MosaicConfig: Codable, Equatable {
    var style = MosaicOps.Style.pixel
    var block = 0.02                    // cell size / blur radius as a fraction of the long side
    var masks: [MaskCanvas] = []
    var coverFaces = false
    var isIdentity: Bool { masks.isEmpty && !coverFaces }
}

/// Finds faces for auto mosaic. Fakeable in tests.
protocol FaceFinding {
    /// Face boxes, normalized, origin bottom-left (Vision space).
    func faceBoxes(in image: CIImage) throws -> [CGRect]
}

struct VisionFaceFinder: FaceFinding {
    func faceBoxes(in image: CIImage) throws -> [CGRect] {
        let cg = CIContext().createCGImage(image, from: image.extent)
        guard let cg else { return [] }
        let a = try ImageAnalysisSync.faces(cg)
        return a.map(\.box)
    }
}

enum ImageAnalysisSync {
    static func faces(_ image: CGImage) throws -> [FaceInfo] {
        let req = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(cgImage: image).perform([req])
        return (req.results ?? []).map { FaceInfo(box: $0.boundingBox, landmarks: [:]) }
    }
}

enum MosaicRender {
    static func apply(_ c: MosaicConfig, to image: CIImage, faces: [CGRect]) -> CIImage {
        guard !c.isIdentity else { return image }
        let e = image.extent
        var mask = CIImage(color: .black).cropped(to: e)
        for m in c.masks {
            mask = MaskScaling.scaled(m, to: e).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: e)
        }
        if c.coverFaces, !faces.isEmpty {
            let regions = AutoMosaic.faceRegions(faces.map { FaceInfo(box: $0, landmarks: [:]) })
            mask = MosaicOps.mask(rects: regions, extent: e).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: e)
        }
        let block = max(c.block, 0.002) * Double(max(e.width, e.height))
        return MosaicOps.apply(c.style, to: image, mask: mask, block: block)
    }
}
