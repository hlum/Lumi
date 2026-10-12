import CoreGraphics

/// Drag math for the crop rectangle. Rects are normalized (0...1, top-left origin) on a picture of `imageSize` pixels.
enum CropMath {
    enum Handle: Equatable { case move, topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right }

    static let minSide = 0.08

    /// Which handle a touch at `p` grabs: corners first, then edges, then the inside. `slop` is in the same units as the rect.
    static func handle(at p: CGPoint, in r: CGRect, slop: CGFloat) -> Handle? {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= slop }
        let l = near(p.x, r.minX), rt = near(p.x, r.maxX), t = near(p.y, r.minY), b = near(p.y, r.maxY)
        if l && t { return .topLeft }; if rt && t { return .topRight }; if l && b { return .bottomLeft }; if rt && b { return .bottomRight }
        let insideX = p.x > r.minX - slop && p.x < r.maxX + slop, insideY = p.y > r.minY - slop && p.y < r.maxY + slop
        if t && insideX { return .top }; if b && insideX { return .bottom }; if l && insideY { return .left }; if rt && insideY { return .right }
        return r.insetBy(dx: -slop, dy: -slop).contains(p) ? .move : nil
    }

    /// New rect after dragging `handle` by `delta` (normalized). `aspect` is width/height in pixels, or nil for free.
    static func drag(_ r: CGRect, handle: Handle, by d: CGPoint, aspect: Double?, imageSize: CGSize) -> CGRect {
        var x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY
        switch handle {
        case .move:
            let w = r.width, h = r.height
            x0 = min(max(r.minX + d.x, 0), 1 - w); y0 = min(max(r.minY + d.y, 0), 1 - h)
            return CGRect(x: x0, y: y0, width: w, height: h)
        case .topLeft: x0 += d.x; y0 += d.y
        case .topRight: x1 += d.x; y0 += d.y
        case .bottomLeft: x0 += d.x; y1 += d.y
        case .bottomRight: x1 += d.x; y1 += d.y
        case .top: y0 += d.y
        case .bottom: y1 += d.y
        case .left: x0 += d.x
        case .right: x1 += d.x
        }
        x0 = min(max(x0, 0), x1 - minSide); y0 = min(max(y0, 0), y1 - minSide)
        x1 = max(min(x1, 1), x0 + minSide); y1 = max(min(y1, 1), y0 + minSide)
        var out = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        guard let aspect, aspect > 0, imageSize.width > 0, imageSize.height > 0 else { return out }
        // locked ratio: keep the opposite corner (or edge midpoint) fixed and fit the rect to the ratio inside the picture
        let k = Double(imageSize.width / imageSize.height) / aspect          // height = width * k
        var w = out.width, h = w * k
        switch handle {
        case .top, .bottom: h = out.height; w = h / k
        default: break
        }
        let anchorX: CGFloat, anchorY: CGFloat
        switch handle {
        case .topLeft: anchorX = r.maxX; anchorY = r.maxY
        case .topRight: anchorX = r.minX; anchorY = r.maxY
        case .bottomLeft: anchorX = r.maxX; anchorY = r.minY
        case .bottomRight: anchorX = r.minX; anchorY = r.minY
        case .top: anchorX = r.midX; anchorY = r.maxY
        case .bottom: anchorX = r.midX; anchorY = r.minY
        case .left: anchorX = r.maxX; anchorY = r.midY
        default: anchorX = r.minX; anchorY = r.midY
        }
        // largest size that fits between the anchor and the picture edge on the dragged side
        let left = [Handle.topLeft, .bottomLeft, .left].contains(handle), up = [Handle.topLeft, .topRight, .top].contains(handle)
        let midX = [Handle.top, .bottom].contains(handle), midY = [Handle.left, .right].contains(handle)
        var maxW = midX ? 2 * min(anchorX, 1 - anchorX) : (left ? anchorX : 1 - anchorX)
        var maxH = midY ? 2 * min(anchorY, 1 - anchorY) : (up ? anchorY : 1 - anchorY)
        maxW = max(maxW, minSide); maxH = max(maxH, minSide)
        var cw = CGFloat(w), ch = CGFloat(h)
        if ch > maxH { ch = maxH; cw = ch / CGFloat(k) }
        if cw > maxW { cw = maxW; ch = cw * CGFloat(k) }
        cw = max(cw, minSide); ch = max(ch, minSide * CGFloat(k))
        let nx = midX ? anchorX - cw / 2 : (left ? anchorX - cw : anchorX)
        let ny = midY ? anchorY - ch / 2 : (up ? anchorY - ch : anchorY)
        out = CGRect(x: nx, y: ny, width: cw, height: ch)
        return out
    }
}
