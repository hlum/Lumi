import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// A 3D color lookup table (RGB in 0...1), blue varies slowest... red fastest, as in .cube files.
struct LUT: Equatable {
    let size: Int
    let rgb: [Float]   // size^3 * 3

    enum ParseError: Error, Equatable { case missingSize, badSize, badCount(expected: Int, got: Int), badLine(Int) }

    init(size: Int, rgb: [Float]) { self.size = size; self.rgb = rgb }

    static func identity(size: Int) -> LUT {
        var v: [Float] = []; v.reserveCapacity(size * size * size * 3)
        let d = Float(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size { v += [Float(r) / d, Float(g) / d, Float(b) / d] } } }
        return LUT(size: size, rgb: v)
    }

    /// Parses Adobe/Resolve `.cube` 3D LUTs. Ignores comments, TITLE and 1D tables are rejected.
    static func parse(cube text: String) throws -> LUT {
        var size: Int?
        var dmin: [Float] = [0, 0, 0], dmax: [Float] = [1, 1, 1]
        var vals: [Float] = []
        for (n, raw) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("TITLE") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            switch parts[0] {
            case "LUT_3D_SIZE":
                guard parts.count == 2, let s = Int(parts[1]), s >= 2, s <= 256 else { throw ParseError.badSize }
                size = s
            case "LUT_1D_SIZE": throw ParseError.badSize
            case "DOMAIN_MIN": dmin = parts.dropFirst().compactMap(Float.init); if dmin.count != 3 { throw ParseError.badLine(n + 1) }
            case "DOMAIN_MAX": dmax = parts.dropFirst().compactMap(Float.init); if dmax.count != 3 { throw ParseError.badLine(n + 1) }
            default:
                let f = parts.compactMap(Float.init)
                guard f.count == 3, parts.count == 3 else { throw ParseError.badLine(n + 1) }
                for i in 0..<3 {
                    let span = dmax[i] - dmin[i]
                    vals.append(span == 0 ? 0 : min(max((f[i] - dmin[i]) / span, 0), 1))
                }
            }
        }
        guard let size else { throw ParseError.missingSize }
        let expected = size * size * size * 3
        guard vals.count == expected else { throw ParseError.badCount(expected: expected / 3, got: vals.count / 3) }
        return LUT(size: size, rgb: vals)
    }

    /// Looks up (r,g,b) with trilinear interpolation. Used by tests and by LUT generation.
    func sample(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
        let d = Float(size - 1)
        func split(_ v: Float) -> (Int, Float) {
            let x = min(max(v, 0), 1) * d
            let i = min(Int(x), size - 2)
            return (i, x - Float(i))
        }
        let (ri, rf) = split(r), (gi, gf) = split(g), (bi, bf) = split(b)
        func at(_ r: Int, _ g: Int, _ b: Int, _ c: Int) -> Float { rgb[((b * size + g) * size + r) * 3 + c] }
        var out: [Float] = [0, 0, 0]
        for c in 0..<3 {
            var acc: Float = 0
            for db in 0...1 { for dg in 0...1 { for dr in 0...1 {
                let w = (dr == 0 ? 1 - rf : rf) * (dg == 0 ? 1 - gf : gf) * (db == 0 ? 1 - bf : bf)
                acc += w * at(ri + dr, gi + dg, bi + db, c)
            } } }
            out[c] = acc
        }
        return (out[0], out[1], out[2])
    }

    /// RGBA float data for CIColorCube.
    var cubeData: Data {
        var f: [Float] = []; f.reserveCapacity(size * size * size * 4)
        for i in 0..<size * size * size { f += [rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2], 1] }
        return f.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Applies the LUT; `intensity` 0 = original, 1 = full.
    func apply(to image: CIImage, intensity: Double = 1) -> CIImage {
        let t = min(max(intensity, 0), 1)
        guard t > 0 else { return image }
        let f = CIFilter.colorCubeWithColorSpace()
        f.inputImage = image; f.cubeDimension = Float(size); f.cubeData = cubeData
        f.colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        guard let out = f.outputImage else { return image }
        guard t < 1 else { return out }
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = image; mix.targetImage = out; mix.time = Float(t)
        return (mix.outputImage ?? out).cropped(to: image.extent)
    }
}
