import SwiftUI
import UIKit

/// Two-finger pinch to zoom and two-finger drag to move around the photo. One finger is left alone, so brushes and handles keep working at any zoom.
struct ZoomBridge: UIViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var pan: CGSize
    static let maxZoom: CGFloat = 6

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> BridgeView { let v = BridgeView(); v.coordinator = context.coordinator; return v }
    func updateUIView(_ view: BridgeView, context: Context) { context.coordinator.parent = self }

    /// Keeps the picture covering the frame: no panning past its edges.
    static func clamped(_ pan: CGSize, zoom: CGFloat, in size: CGSize) -> CGSize {
        let mx = size.width * (zoom - 1) / 2, my = size.height * (zoom - 1) / 2
        return CGSize(width: min(max(pan.width, -mx), mx), height: min(max(pan.height, -my), my))
    }

    final class BridgeView: UIView {
        weak var coordinator: Coordinator?
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError() }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let c = coordinator else { return }
            c.attach(to: window, view: self)
        }
        override func willMove(toWindow newWindow: UIWindow?) { if newWindow == nil { coordinator?.detach() } }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ZoomBridge
        private weak var host: UIWindow?
        private weak var bridge: UIView?
        private let pinch = UIPinchGestureRecognizer(), drag = UIPanGestureRecognizer()
        init(_ p: ZoomBridge) { parent = p }

        func attach(to window: UIWindow, view: UIView) {
            guard host !== window else { return }
            detach()
            host = window; bridge = view
            pinch.addTarget(self, action: #selector(pinched)); drag.addTarget(self, action: #selector(dragged))
            drag.minimumNumberOfTouches = 2
            for g in [pinch, drag] as [UIGestureRecognizer] { g.delegate = self; g.cancelsTouchesInView = false; window.addGestureRecognizer(g) }
        }
        func detach() { for g in [pinch, drag] as [UIGestureRecognizer] { host?.removeGestureRecognizer(g) }; host = nil }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let bridge, let host else { return false }
            return bridge.bounds.contains(bridge.convert(g.location(in: host), from: host))
        }
        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool { true }

        @objc private func pinched(_ g: UIPinchGestureRecognizer) {
            guard let bridge, g.state == .changed || g.state == .ended else { return }
            let old = parent.zoom, new = min(max(old * g.scale, 1), ZoomBridge.maxZoom)
            g.scale = 1
            // keep the point under the fingers where it is
            let p = bridge.convert(g.location(in: host), from: host)
            let c = CGPoint(x: p.x - bridge.bounds.midX, y: p.y - bridge.bounds.midY), k = new / old
            var pan = CGSize(width: c.x * (1 - k) + parent.pan.width * k, height: c.y * (1 - k) + parent.pan.height * k)
            pan = ZoomBridge.clamped(pan, zoom: new, in: bridge.bounds.size)
            parent.zoom = new; parent.pan = new == 1 ? .zero : pan
        }
        @objc private func dragged(_ g: UIPanGestureRecognizer) {
            guard let bridge, g.state == .changed, parent.zoom > 1 else { return }
            let t = g.translation(in: host); g.setTranslation(.zero, in: host)
            parent.pan = ZoomBridge.clamped(CGSize(width: parent.pan.width + t.x, height: parent.pan.height + t.y), zoom: parent.zoom, in: bridge.bounds.size)
        }
    }
}
