// Renders the app icon (1024x1024) with Core Graphics. Run: swift scripts/make_icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let colors = [CGColor(red: 1.0, green: 0.55, blue: 0.62, alpha: 1), CGColor(red: 0.45, green: 0.35, blue: 0.95, alpha: 1)] as CFArray
let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(size)), end: CGPoint(x: CGFloat(size), y: 0), options: [])

// a four-point sparkle
func sparkle(cx: CGFloat, cy: CGFloat, r: CGFloat) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: cy + r))
    p.addQuadCurve(to: CGPoint(x: cx + r, y: cy), control: CGPoint(x: cx + r * 0.08, y: cy + r * 0.08))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy - r), control: CGPoint(x: cx + r * 0.08, y: cy - r * 0.08))
    p.addQuadCurve(to: CGPoint(x: cx - r, y: cy), control: CGPoint(x: cx - r * 0.08, y: cy - r * 0.08))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy + r), control: CGPoint(x: cx - r * 0.08, y: cy + r * 0.08))
    ctx.addPath(p); ctx.fillPath()
}
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
sparkle(cx: 480, cy: 540, r: 330)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
sparkle(cx: 770, cy: 790, r: 120)
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
sparkle(cx: 790, cy: 320, r: 80)

let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest))
print("wrote \(out)")
