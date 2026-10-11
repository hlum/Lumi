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
    struct Built { var composition: AVMutableComposition; var audioMix: AVAudioMix?; var videoComposition: AVVideoComposition?; var renderSize: CGSize = .zero }

    /// Lays clips on two alternating video tracks so neighbours can overlap for a transition, and builds the instructions the compositor follows.
    static func build(_ timeline: Timeline, options: VideoExportOptions = VideoExportOptions(), resolve: (TimelineClip.Source) async throws -> AVAsset) async throws -> Built {
        guard !timeline.isEmpty else { throw VideoError.emptyTimeline }
        let comp = AVMutableComposition()
        var vTracks: [AVMutableCompositionTrack] = []
        for _ in 0..<2 {
            guard let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw VideoError.noVideoTrack }
            vTracks.append(t)
        }
        // audio tracks are created only when a clip really has audio: an empty track makes export fail
        var aTracks: [AVMutableCompositionTrack?] = [nil, nil]
        var aParams: [AVMutableAudioMixInputParameters?] = [nil, nil]
        let starts = timeline.starts
        var size = CGSize.zero

        for (i, clip) in timeline.clips.enumerated() {
            let lane = i % 2
            let asset = try await resolve(clip.source)
            guard let srcV = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideoTrack }
            if size == .zero {
                let n = try await srcV.load(.naturalSize), tf = try await srcV.load(.preferredTransform), d = n.applying(tf)
                size = CGSize(width: abs(d.width), height: abs(d.height))
            }
            let assetDuration = try await asset.load(.duration)
            let start = CMTime(seconds: min(clip.sourceStart, max(assetDuration.seconds - 0.01, 0)), preferredTimescale: 600)
            let len = CMTime(seconds: min(clip.sourceDuration, max(assetDuration.seconds - start.seconds, 0.01)), preferredTimescale: 600)
            let range = CMTimeRange(start: start, duration: len)
            let at = CMTime(seconds: starts[i], preferredTimescale: 600)
            try vTracks[lane].insertTimeRange(range, of: srcV, at: at)
            if let srcA = try await asset.loadTracks(withMediaType: .audio).first {
                if aTracks[lane] == nil {
                    aTracks[lane] = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    aParams[lane] = aTracks[lane].map { AVMutableAudioMixInputParameters(track: $0) }
                }
                try aTracks[lane]?.insertTimeRange(range, of: srcA, at: at)
                aParams[lane]?.setVolume(Float(clip.volume), at: at)
            }
            let speed = min(max(clip.speed, 0.1), 8)
            if speed != 1 {
                let inserted = CMTimeRange(start: at, duration: len)
                let newLen = CMTime(seconds: len.seconds / speed, preferredTimescale: 600)
                vTracks[lane].scaleTimeRange(inserted, toDuration: newLen)
                aTracks[lane]?.scaleTimeRange(inserted, toDuration: newLen)
            }
        }

        let render = options.outputSize(for: size)
        // Instructions tile the whole timeline: clip bodies and transition overlaps.
        var instructions: [LumiInstruction] = []
        let clips = timeline.clips
        func layer(_ i: Int) -> LumiInstruction.Layer {
            LumiInstruction.Layer(trackID: vTracks[i % 2].trackID, look: clips[i].look, layout: clips[i].layout)
        }
        func time(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }
        for i in clips.indices {
            let end = starts[i] + clips[i].duration
            let bodyStart = starts[i] + timeline.overlap(at: i)
            let nextOverlap = i + 1 < clips.count ? timeline.overlap(at: i + 1) : 0
            let bodyEnd = end - nextOverlap
            if bodyEnd > bodyStart + 0.0005 {
                instructions.append(LumiInstruction(timeRange: CMTimeRange(start: time(bodyStart), end: time(bodyEnd)), from: layer(i), to: nil, transition: .none, renderSize: render))
            }
            if nextOverlap > 0 {
                instructions.append(LumiInstruction(timeRange: CMTimeRange(start: time(bodyEnd), end: time(end)), from: layer(i), to: layer(i + 1), transition: clips[i + 1].transition, renderSize: render))
            }
        }
        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = LumiCompositor.self
        vc.renderSize = render
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(options.normalizedFPS))
        vc.instructions = instructions

        let used = aParams.compactMap { $0 }
        var mix: AVMutableAudioMix?
        if !used.isEmpty { mix = AVMutableAudioMix(); mix?.inputParameters = used }
        return Built(composition: comp, audioMix: mix, videoComposition: vc, renderSize: render)
    }
}

enum VideoExporter {
    static func export(_ built: VideoComposer.Built, options: VideoExportOptions, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let preset: String
        switch options.resolution { case .p720: preset = AVAssetExportPreset1280x720; case .p1080: preset = AVAssetExportPreset1920x1080; case .p2160: preset = AVAssetExportPreset3840x2160 }
        guard let session = AVAssetExportSession(asset: built.composition, presetName: preset) else { throw VideoError.exportFailed("no session") }
        session.videoComposition = built.videoComposition; session.audioMix = built.audioMix
        do { try await session.export(to: url, as: .mp4) } catch { throw VideoError.exportFailed(String(describing: error)) }
    }
}
