import CoreImage

/// Lipstick that keeps the lip's own light: brightness and creases come from the photo, colour from the lipstick,
/// and the finish is a change to the highlights (gloss lifts them, matte flattens them), as real lipstick does.
enum LipTint {
    private static let source = """
    #include <metal_stdlib>
    #include <CoreImage/CoreImage.h>
    using namespace metal;
    extern "C" { namespace coreimage {
    [[ stitchable ]] float4 lipTint(sample_t s, float3 target, float meanL, float gloss, float matte) {
        float3 c = pow(max(s.rgb, 0.0), 1.0 / 2.2);
        float3 t = target;                                   // the lipstick colour is given in display values already
        float3 w = float3(0.2126, 0.7152, 0.0722);
        float y = dot(c, w), ty = dot(t, w);
        // keep the lip's own light and texture, move its average lightness to the lipstick's
        float ny = y + (ty - meanL) * 0.6;
        // the lipstick's colour, richer where the lip is lit and deeper in its shadows
        float k = clamp(y / max(meanL, 0.05), 0.5, 1.5);
        float3 chroma = mix(c - y, (t - ty) * 0.8, 0.85) * k;   // mostly the lipstick, a little of the lip's own colour, less than full paint saturation
        float hi = smoothstep(meanL + 0.03, meanL + 0.3, y);
        ny += gloss * hi * 0.18 * (1.0 - ny);                    // wet highlights, never blown out
        ny -= matte * max(ny - ty - 0.02, 0.0) * 0.75;            // powdery: highlights pressed down
        float3 o = clamp(ny + chroma, 0.0, 1.0);
        return float4(pow(o, 2.2), s.a);
    }
    }}
    """
    private static let kernel: CIColorKernel? = try? CIColorKernel.kernels(withMetalString: source).first as? CIColorKernel

    static func finish(_ f: MakeupParams.Finish) -> (gloss: Float, matte: Float) {
        switch f { case .matte: (0, 1); case .satin: (0.3, 0.3); case .gloss: (1, 0) }
    }

    /// Average display brightness (0...1) of `image` under `mask`.
    static func meanLuma(_ image: CIImage, mask: CIImage) -> Float {
        let e = image.extent, ctx = CIContext()
        let masked = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .black).cropped(to: e), kCIInputMaskImageKey: mask])
        func avg(_ i: CIImage) -> [Float] {
            var px = [Float](repeating: 0, count: 4)
            ctx.render(i.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: e)]), toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return px
        }
        let m = avg(mask)[0], c = avg(masked)
        guard m > 1e-4 else { return 0.4 }
        return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / m
    }

    /// The whole picture recoloured as lipstick; blend it in through the lip mask.
    static func apply(_ image: CIImage, color: RGBA, finish f: MakeupParams.Finish, meanL: Float) -> CIImage {
        guard let kernel else { return image }
        let (g, m) = finish(f)
        return kernel.apply(extent: image.extent, arguments: [image, CIVector(x: color.r, y: color.g, z: color.b), meanL, g, m]) ?? image
    }
}
