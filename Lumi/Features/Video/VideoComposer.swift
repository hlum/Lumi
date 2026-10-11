import AVFoundation
import CoreImage
import Foundation

enum VideoError: Error, Equatable { case noVideoTrack, emptyTimeline, writerFailed, exportFailed(String) }

/// Makes a short video from one still image, so photos can sit on the timeline like any clip.
enum StillVideo {
    static func make(_ image: CIImage, seconds: Double, size: CGSize, fps: Int = 30) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let w = Int(size.width) / 2 * 2, h = Int(size.height) / 2 * 2
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        guard writer.canAdd(input) else { throw VideoError.writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw VideoError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        // scale the image to fill the frame
        let e = image.extent
        let fitted = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY).scaledBy(x: CGFloat(w) / e.width, y: CGFloat(h) / e.height))
        let ctx = CIContext()
        let frames = max(1, Int((seconds * Double(fps)).rounded()))
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, nil, &pb)
            guard let pb else { throw VideoError.writerFailed }
            ctx.render(fitted, to: pb)
            guard adaptor.append(pb, withPresentationTime: CMTime(value: Int64(i), timescale: CMTimeScale(fps))) else { throw VideoError.writerFailed }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw VideoError.writerFailed }
        return url
    }
}

enum VideoComposer {
    struct Built { var composition: AVMutableComposition; var audioMix: AVAudioMix?; var videoComposition: AVVideoComposition? }

    /// Lays the timeline's clips end to end. `resolve` turns a clip source into a playable asset (photos: a still video).
    static func build(_ timeline: Timeline, resolve: (TimelineClip.Source) async throws -> AVAsset) async throws -> Built {
        guard !timeline.isEmpty else { throw VideoError.emptyTimeline }
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VideoError.noVideoTrack }
        // the audio track is created only when a clip really has audio: an empty track makes export fail
        var aTrack: AVMutableCompositionTrack?
        var audioParams: AVMutableAudioMixInputParameters?
        var cursor = CMTime.zero

        for clip in timeline.clips {
            let asset = try await resolve(clip.source)
            guard let srcV = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideoTrack }
            let assetDuration = try await asset.load(.duration)
            let start = CMTime(seconds: min(clip.sourceStart, max(assetDuration.seconds - 0.01, 0)), preferredTimescale: 600)
            let len = CMTime(seconds: min(clip.sourceDuration, max(assetDuration.seconds - start.seconds, 0.01)), preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: len)
            try vTrack.insertTimeRange(range, of: srcV, at: cursor)
            if let srcA = try await asset.loadTracks(withMediaType: .audio).first {
                if aTrack == nil {
                    aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    audioParams = aTrack.map { AVMutableAudioMixInputParameters(track: $0) }
                }
                try aTrack?.insertTimeRange(range, of: srcA, at: cursor)
                audioParams?.setVolume(Float(clip.volume), at: cursor)
            }
            let speed = min(max(clip.speed, 0.1), 8)
            if speed != 1 {
                let inserted = CMTimeRange(start: cursor, duration: len)
                comp.scaleTimeRange(inserted, toDuration: CMTime(seconds: len.seconds / speed, preferredTimescale: 600))
            }
            cursor = CMTimeAdd(cursor, CMTime(seconds: len.seconds / speed, preferredTimescale: 600))
        }
        var mix: AVMutableAudioMix?
        if let audioParams { mix = AVMutableAudioMix(); mix?.inputParameters = [audioParams] }
        return Built(composition: comp, audioMix: mix, videoComposition: nil)
    }
}

enum VideoExporter {
    static func export(_ built: VideoComposer.Built, options: VideoExportOptions, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let asset = built.composition
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideoTrack }
        let natural = try await track.load(.naturalSize), transform = try await track.load(.preferredTransform)
        let displayed = natural.applying(transform)
        let size = options.outputSize(for: CGSize(width: abs(displayed.width), height: abs(displayed.height)))

        let vc = AVMutableVideoComposition(propertiesOf: asset)
        vc.renderSize = size
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(options.normalizedFPS))
        // scale the single video track to the render size
        let inst = AVMutableVideoCompositionInstruction(); inst.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform.concatenating(CGAffineTransform(scaleX: size.width / max(abs(displayed.width), 1), y: size.height / max(abs(displayed.height), 1))), at: .zero)
        inst.layerInstructions = [layer]; vc.instructions = [inst]

        let preset: String
        switch options.resolution { case .p720: preset = AVAssetExportPreset1280x720; case .p1080: preset = AVAssetExportPreset1920x1080; case .p2160: preset = AVAssetExportPreset3840x2160 }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw VideoError.exportFailed("no session") }
        session.videoComposition = vc; session.audioMix = built.audioMix
        do { try await session.export(to: url, as: .mp4) } catch { throw VideoError.exportFailed(String(describing: error)) }
    }
}
