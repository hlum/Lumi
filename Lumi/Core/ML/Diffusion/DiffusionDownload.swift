import Foundation
import Observation

/// One-time download of the Stable Diffusion inpainting model (DreamShaper 8 Inpainting, Core ML fp16, by Lykon, converted by LocalMuseAI).
/// CreativeML Open RAIL-M licence: https://huggingface.co/spaces/CompVis/stable-diffusion-license
@Observable
final class DiffusionDownload: NSObject, URLSessionDownloadDelegate {
    static let shared = DiffusionDownload()
    static let source = "https://huggingface.co/LocalMuseAI/coreml-dreamshaper-8-inpaint-fp16/resolve/main/"
    /// Every file with its exact size, so a half-finished download is never mistaken for a finished one.
    static let files: [(path: String, size: Int)] = [
        ("LICENSE", 14385),
        ("TextEncoder.mlmodelc/analytics/coremldata.bin", 243),
        ("TextEncoder.mlmodelc/coremldata.bin", 982),
        ("TextEncoder.mlmodelc/metadata.json", 3019),
        ("TextEncoder.mlmodelc/model.mil", 170454),
        ("TextEncoder.mlmodelc/weights/weight.bin", 246145536),
        ("UnetChunk1.mlmodelc/analytics/coremldata.bin", 243),
        ("UnetChunk1.mlmodelc/coremldata.bin", 968),
        ("UnetChunk1.mlmodelc/metadata.json", 6890),
        ("UnetChunk1.mlmodelc/model.mil", 1314670),
        ("UnetChunk1.mlmodelc/weights/weight.bin", 887598400),
        ("UnetChunk2.mlmodelc/analytics/coremldata.bin", 243),
        ("UnetChunk2.mlmodelc/coremldata.bin", 949),
        ("UnetChunk2.mlmodelc/metadata.json", 6574),
        ("UnetChunk2.mlmodelc/model.mil", 1768411),
        ("UnetChunk2.mlmodelc/weights/weight.bin", 831567872),
        ("VAEDecoder.mlmodelc/analytics/coremldata.bin", 243),
        ("VAEDecoder.mlmodelc/coremldata.bin", 909),
        ("VAEDecoder.mlmodelc/metadata.json", 2725),
        ("VAEDecoder.mlmodelc/model.mil", 194902),
        ("VAEDecoder.mlmodelc/weights/weight.bin", 98993280),
        ("VAEEncoder.mlmodelc/analytics/coremldata.bin", 243),
        ("VAEEncoder.mlmodelc/coremldata.bin", 913),
        ("VAEEncoder.mlmodelc/metadata.json", 2709),
        ("VAEEncoder.mlmodelc/model.mil", 149287),
        ("VAEEncoder.mlmodelc/weights/weight.bin", 68338112),
        ("merges.txt", 524619),
        ("vocab.json", 1059962)
    ]
    static var totalBytes: Int { files.reduce(0) { $0 + $1.size } }

    static func isComplete(at dir: URL) -> Bool {
        files.allSatisfy { f in
            let attrs = try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(f.path).path)
            return (attrs?[.size] as? Int) == f.size
        }
    }

    enum State: Equatable { case idle, downloading(Double), failed(String) }
    private(set) var state = State.idle
    var isInstalled: Bool { Self.isComplete(at: DiffusionInpainter.installDirectory) }

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var doneBytes = 0
    @ObservationIgnored private var currentFileBytes = 0
    @ObservationIgnored private var continuation: CheckedContinuation<URL, Error>?

    func start() {
        guard task == nil else { return }
        state = .downloading(0)
        task = Task { [weak self] in await self?.run() }
    }

    func cancel() { task?.cancel(); session?.invalidateAndCancel(); task = nil; state = .idle }

    func remove() {
        cancel()
        try? FileManager.default.removeItem(at: DiffusionInpainter.installDirectory)
        ModelStore.shared.noteChanged()
    }

    private func run() async {
        let dir = DiffusionInpainter.installDirectory
        let cfg = URLSessionConfiguration.default; cfg.waitsForConnectivity = true
        let session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        self.session = session
        defer { task = nil; self.session = nil }
        do {
            doneBytes = 0
            for f in Self.files {
                try Task.checkCancellation()
                let dest = dir.appendingPathComponent(f.path)
                if (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) == f.size { doneBytes += f.size; publish(); continue }
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                currentFileBytes = 0
                let tmp = try await download(URL(string: Self.source + f.path)!, with: session)
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                guard (try FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) == f.size else { throw URLError(.cannotParseResponse) }
                doneBytes += f.size; publish()
            }
            state = .idle
            ModelStore.shared.noteChanged()
        } catch is CancellationError { state = .idle }
        catch { if (error as? URLError)?.code != .cancelled { state = .failed(error.localizedDescription) } }
    }

    private func publish() { state = .downloading(Double(doneBytes + currentFileBytes) / Double(Self.totalBytes)) }

    private func download(_ url: URL, with session: URLSession) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            continuation = c
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten written: Int64, totalBytesExpectedToWrite _: Int64) {
        currentFileBytes = Int(written); publish()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // the system deletes `location` when this returns: keep our own copy
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw URLError(.badServerResponse) }
            try FileManager.default.moveItem(at: location, to: keep)
            continuation?.resume(returning: keep)
        } catch { continuation?.resume(throwing: error) }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, let c = continuation { continuation = nil; c.resume(throwing: error) }
    }
}
