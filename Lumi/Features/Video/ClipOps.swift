import AVFoundation
import CoreImage
import Foundation

enum ClipOps {
    /// A still video of the frame at `time`, held for `hold` seconds (freeze frame).
    static func freezeFrame(of asset: AVAsset, at time: Double, hold: Double) async throws -> URL {
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let cg = try await gen.image(at: CMTime(seconds: max(time, 0), preferredTimescale: 600)).image
        return try await StillVideo.make(CIImage(cgImage: cg), seconds: hold, size: CGSize(width: cg.width, height: cg.height))
    }

    static let maxReverseFrames = 900     // ~30 s at 30 fps; reversing needs every frame in memory

    /// Renders the clip backwards (video only). Fails for clips longer than `maxReverseFrames`.
    static func reversed(_ asset: AVAsset) async throws -> URL {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideoTrack }
        let size = try await track.load(.naturalSize), fps = max(try await track.load(.nominalFrameRate), 1)
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(out)
        guard reader.startReading() else { throw VideoError.writerFailed }
        var frames: [CVPixelBuffer] = []
        while let sb = out.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            guard frames.count < maxReverseFrames else { throw VideoError.exportFailed("clip too long to reverse") }
            frames.append(try copy(pb))
        }
        guard !frames.isEmpty else { throw VideoError.noVideoTrack }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let w = Int(size.width) / 2 * 2, h = Int(size.height) / 2 * 2
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw VideoError.writerFailed }
        writer.startSession(atSourceTime: .zero)
        for (i, pb) in frames.reversed().enumerated() {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard adaptor.append(pb, withPresentationTime: CMTime(value: Int64(i), timescale: CMTimeScale(fps.rounded()))) else { throw VideoError.writerFailed }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw VideoError.writerFailed }
        return url
    }

    private static func copy(_ pb: CVPixelBuffer) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        CVPixelBufferCreate(nil, CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), CVPixelBufferGetPixelFormatType(pb), nil, &out)
        guard let out else { throw VideoError.writerFailed }
        CVPixelBufferLockBaseAddress(pb, .readOnly); CVPixelBufferLockBaseAddress(out, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly); CVPixelBufferUnlockBaseAddress(out, []) }
        for plane in 0..<max(CVPixelBufferGetPlaneCount(pb), 1) {
            let isPlanar = CVPixelBufferGetPlaneCount(pb) > 0
            let src = isPlanar ? CVPixelBufferGetBaseAddressOfPlane(pb, plane) : CVPixelBufferGetBaseAddress(pb)
            let dst = isPlanar ? CVPixelBufferGetBaseAddressOfPlane(out, plane) : CVPixelBufferGetBaseAddress(out)
            let rows = isPlanar ? CVPixelBufferGetHeightOfPlane(pb, plane) : CVPixelBufferGetHeight(pb)
            let sb = isPlanar ? CVPixelBufferGetBytesPerRowOfPlane(pb, plane) : CVPixelBufferGetBytesPerRow(pb)
            let db = isPlanar ? CVPixelBufferGetBytesPerRowOfPlane(out, plane) : CVPixelBufferGetBytesPerRow(out)
            for r in 0..<rows { memcpy(dst! + r * db, src! + r * sb, min(sb, db)) }
        }
        return out
    }

    // MARK: per-frame geometry (applied by the compositor to every frame of a clip)

    struct FrameLayout: Codable, Equatable {
        var crop = CropSpec()
        var mirror = false
        var canvasAspect: Double?               // w/h of the output canvas, nil = source aspect
        var background = RGBA.black
    }

    /// Crops/rotates/mirrors a frame, then fits it onto the canvas over the background.
    static func layout(_ frame: CIImage, _ l: FrameLayout, canvas: CGSize) -> CIImage {
        var img = GeometryOps.apply(l.crop, to: frame)
        if l.mirror { let e = img.extent; img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -e.width - 2 * e.minX, y: 0)) }
        let target = CGRect(origin: .zero, size: canvas)
        let e = img.extent
        let s = min(canvas.width / max(e.width, 1), canvas.height / max(e.height, 1))
        let fitted = img.transformed(by: CGAffineTransform(scaleX: s, y: s).translatedBy(x: -e.minX, y: -e.minY))
        let placed = fitted.transformed(by: CGAffineTransform(translationX: (canvas.width - fitted.extent.width) / 2, y: (canvas.height - fitted.extent.height) / 2))
        let bg = CIImage(color: CIColor(red: l.background.r, green: l.background.g, blue: l.background.b)).cropped(to: target)
        return placed.composited(over: bg).cropped(to: target)
    }
}
