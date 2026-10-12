import CoreImage
import MetalKit
import SwiftUI

/// GPU preview: SwiftUI `Image` can't redraw a Core Image graph at 60 fps, so this wraps an MTKView.
struct MetalPreviewView: UIViewRepresentable {
    var image: CIImage?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.framebufferOnly = false
        v.isOpaque = false; v.backgroundColor = .clear; v.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        v.enableSetNeedsDisplay = true
        v.isPaused = true
        v.delegate = context.coordinator
        context.coordinator.attach(v)
        return v
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.image = image
        view.setNeedsDisplay()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var image: CIImage?
        private var queue: MTLCommandQueue?
        private var context: CIContext?

        func attach(_ v: MTKView) {
            guard let d = v.device else { return }
            queue = d.makeCommandQueue()
            context = CIContext(mtlDevice: d)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let image, let queue, let context, let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer() else { return }
            let size = view.drawableSize
            let fit = min(size.width / image.extent.width, size.height / image.extent.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: fit, y: fit))
            let dx = (size.width - scaled.extent.width) / 2 - scaled.extent.minX
            let dy = (size.height - scaled.extent.height) / 2 - scaled.extent.minY
            let out = scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
            // clear first: anything outside the picture must be transparent, not whatever the drawable held before
            let bounds = CGRect(origin: .zero, size: size)
            let onClear = out.composited(over: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: bounds))
            context.render(onClear, to: drawable.texture, commandBuffer: buffer,
                           bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB())
            buffer.present(drawable)
            buffer.commit()
        }
    }
}
