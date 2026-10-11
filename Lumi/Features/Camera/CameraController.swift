import AVFoundation
import CoreImage
import Observation
import SwiftUI

/// Wraps an AVCaptureSession. Frames arrive as CIImages; `process` styles them (filter, beauty) before they reach the preview,
/// so the live view and the saved photo go through the same render path as the editor.
@Observable
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "lumi.camera")
    private let lock = NSLock()
    private var currentSettings = CameraSettings()
    private var pending: ((Data?) -> Void)?

    private(set) var latestFrame: CIImage?
    private(set) var authorized = false
    var settings: CameraSettings {
        get { lock.lock(); defer { lock.unlock() }; return currentSettings }
        set { lock.lock(); currentSettings = newValue; lock.unlock(); queue.async { self.configureInput() } }
    }

    func start() async {
        authorized = await AVCaptureDevice.requestAccess(for: .video)
        guard authorized else { return }
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
            self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            self.session.commitConfiguration()
            self.configureInput()
            self.session.startRunning()
        }
    }

    func stop() { queue.async { self.session.stopRunning() } }

    private func configureInput() {
        let s = settings
        let position: AVCaptureDevice.Position = s.lens == .front ? .front : .back
        let type: AVCaptureDevice.DeviceType = s.lens == .ultraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
        guard let device = AVCaptureDevice.default(type, for: .video, position: position) ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        if session.canAddInput(input) { session.addInput(input) }
        if let c = videoOutput.connection(with: .video) {
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            c.isVideoMirrored = position == .front && s.mirrorFront
        }
        session.commitConfiguration()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestFrame = CameraPipeline.process(CIImage(cvPixelBuffer: pb), settings: settings)
    }

    func capture() async -> Data? {
        await withCheckedContinuation { cont in
            queue.async {
                self.pending = { cont.resume(returning: $0) }
                let s = AVCapturePhotoSettings()
                if self.photoOutput.supportedFlashModes.contains(.on) {
                    switch self.settings.hardwareFlash { case .off: s.flashMode = .off; case .auto: s.flashMode = .auto; case .on: s.flashMode = .on }
                }
                self.photoOutput.capturePhoto(with: s, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let done = pending; pending = nil
        done?(data)
    }
}

/// Styling shared by the live preview and the shutter. Pure, so it is unit-tested.
enum CameraPipeline {
    static func process(_ frame: CIImage, settings: CameraSettings) -> CIImage {
        var doc = EditDocument()
        if let id = settings.lookID { doc.filter = (id, 1) }
        var img = Renderer.render(frame, document: doc)
        if settings.beauty > 0 {
            var p = AutoBeauty.scaled(AutoBeauty.looks[0], strength: settings.beauty).skin
            p.smooth = min(p.smooth + settings.beauty * 0.2, 1)
            // whole-frame softening while no face mask is available at preview speed; the editor applies the precise mask later
            img = SkinOps.apply(p, to: img, mask: CIImage(color: .white).cropped(to: img.extent))
        }
        let crop = settings.cropRect(for: img.extent.size)
        return img.cropped(to: CGRect(x: img.extent.minX + crop.minX, y: img.extent.minY + (img.extent.height - crop.maxY), width: crop.width, height: crop.height))
    }
}
