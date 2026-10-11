import Vision
import CoreImage
import Foundation

/// Mosaic as a document operation: brushed/boxed masks plus optional automatic face cover.
struct MosaicConfig: Codable, Equatable {
    var style = MosaicOps.Style.pixel
    var block = 0.02                    // cell size / blur radius as a fraction of the long side
    var masks: [MaskCanvas] = []
    var coverFaces = false
    var chatMode = false                // cover avatars and names found in a chat screenshot
    var isIdentity: Bool { masks.isEmpty && !coverFaces && !chatMode }

    init() {}
    enum CodingKeys: String, CodingKey { case style, block, masks, coverFaces, chatMode }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        style = try c.decodeIfPresent(MosaicOps.Style.self, forKey: .style) ?? .pixel
        block = try c.decodeIfPresent(Double.self, forKey: .block) ?? 0.02
        masks = try c.decodeIfPresent([MaskCanvas].self, forKey: .masks) ?? []
        coverFaces = try c.decodeIfPresent(Bool.self, forKey: .coverFaces) ?? false
        chatMode = try c.decodeIfPresent(Bool.self, forKey: .chatMode) ?? false
    }
}

/// Finds faces for auto mosaic. Fakeable in tests.
/// Finds text lines (for chat-screenshot mosaic). Fakeable in tests.
protocol TextFinding {
    /// Text boxes, normalized, origin bottom-left (Vision space).
    func textBoxes(in image: CIImage) throws -> [CGRect]
}

struct VisionTextFinder: TextFinding {
    func textBoxes(in image: CIImage) throws -> [CGRect] {
        let req = VNRecognizeTextRequest(); req.recognitionLevel = .fast
        try VNImageRequestHandler(ciImage: image).perform([req])
        return (req.results ?? []).map(\.boundingBox)
    }
}

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
    static func apply(_ c: MosaicConfig, to image: CIImage, faces: [CGRect], textBoxes: [CGRect] = []) -> CIImage {
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
        if c.chatMode, !textBoxes.isEmpty {
            let regions = AutoMosaic.chatRegions(textBoxes: textBoxes, imageAspect: e.width / e.height)
            mask = MosaicOps.mask(rects: regions, extent: e).applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: mask]).cropped(to: e)
        }
        let block = max(c.block, 0.002) * Double(max(e.width, e.height))
        return MosaicOps.apply(c.style, to: image, mask: mask, block: block)
    }
}
