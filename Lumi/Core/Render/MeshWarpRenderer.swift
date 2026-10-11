import CoreImage
import Foundation

/// Applies a `DisplacementField` to an image on the GPU through a Core Image Metal kernel.
enum MeshWarpRenderer {
    static let maxOffset: Float = 0.5

    // Compiled from source at first use: no Metal build flags needed, and Xcode Cloud builds it the same way.
    private static let source = """
    #include <metal_stdlib>
    #include <CoreImage/CoreImage.h>
    using namespace metal;
    extern "C" { namespace coreimage {
    // Samples the source at (uv + offset(uv)). `fld` holds offset + 0.5 in RG (0.5 = no move) as a small grid image.
    [[ stitchable ]] float4 meshWarp(sampler src, sampler fld, float2 imageSize, float2 fieldSize, destination dest) {
        float2 uv = dest.coord() / imageSize;
        float2 fp = uv * (fieldSize - 1.0) + 0.5;
        float2 off = fld.sample(fld.transform(fp)).rg - 0.5;
        float2 q = (uv + off) * imageSize;
        return src.sample(src.transform(q));
    }
    }}
    """

    private static let loaded: (kernel: CIKernel?, error: String?) = {
        do { return (try CIKernel.kernels(withMetalString: source).first, nil) }
        catch { return (nil, String(describing: error)) }
    }()
    /// Why the kernel isn't available, or nil when it loaded.
    static var loadError: String? { loaded.kernel == nil ? (loaded.error ?? "no kernel") : nil }
    private static var kernel: CIKernel? { loaded.kernel }

    /// The field as a small float image: R,G = offset + 0.5. CI's y axis is up, the field's is down, so dy flips.
    static func fieldImage(_ f: DisplacementField) -> CIImage {
        var px: [Float] = []; px.reserveCapacity(f.cols * f.rows * 4)
        for j in 0..<f.rows { for i in 0..<f.cols {
            let (dx, dy) = f.offset(x: Float(i) / Float(f.cols - 1), y: Float(j) / Float(f.rows - 1))
            let cx = min(max(dx, -maxOffset), maxOffset), cy = min(max(-dy, -maxOffset), maxOffset)
            px += [cx + 0.5, cy + 0.5, 0, 1]
        } }
        // grid row 0 is the image top (y down); CI row 0 is the bottom, so write rows reversed
        var rows: [Float] = []
        for j in (0..<f.rows).reversed() { rows += px[(j * f.cols * 4)..<((j + 1) * f.cols * 4)] }
        let data = rows.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: f.cols * 16, size: CGSize(width: f.cols, height: f.rows), format: .RGBAf, colorSpace: nil)
    }

    static func apply(_ field: DisplacementField, to image: CIImage) -> CIImage {
        guard !field.isIdentity, let kernel else { return image }
        let e = image.extent
        let src = image.clampedToExtent().transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        let fld = fieldImage(field)
        let out = kernel.apply(extent: CGRect(origin: .zero, size: e.size),
                               roiCallback: { index, rect in index == 0 ? CGRect(origin: .zero, size: e.size).insetBy(dx: -2, dy: -2) : fld.extent },
                               arguments: [src, fld, CIVector(x: e.width, y: e.height), CIVector(x: CGFloat(field.cols), y: CGFloat(field.rows))])
        return out?.transformed(by: CGAffineTransform(translationX: e.minX, y: e.minY)) ?? image
    }
}
