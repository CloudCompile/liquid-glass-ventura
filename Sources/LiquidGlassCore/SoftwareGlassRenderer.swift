import Foundation

/// A CPU implementation of the reference liquid-glass fragment shader.
///
/// This exists for three reasons:
///
/// 1. It is the reference oracle. The Metal shader is validated against it, so
///    any drift between the two shows up as a test failure rather than a
///    visual regression.
/// 2. It lets the whole optical pipeline run on Linux, which is how the
///    screenshots in `docs/` are produced and checked in CI.
/// 3. It gives apps a software fallback when no Metal device is available.
///
/// The math is a line-by-line translation of the GLSL in the web reference;
/// see `GlassMath` for the shared geometry.
public struct SoftwareGlassRenderer {

    /// The scene behind the panel, already cropped to the panel's padded box.
    public var backdrop: RGBAImage

    public init(backdrop: RGBAImage) {
        self.backdrop = backdrop
    }

    /// Separable 9-tap Gaussian, `glassBlurIterations` passes, matching the
    /// reference `FS_BLUR` kernel weights exactly.
    ///
    /// Works on `Float` channel buffers rather than the 8-bit image so the
    /// repeated passes do not quantise, and so the inner loops stay tight.
    public static func blur(_ image: RGBAImage, amount: Double) -> RGBAImage {
        guard amount > 0, !image.isEmpty else { return image }
        let w = image.width
        let h = image.height
        let spread = amount * 2.5

        var a = [Float](repeating: 0, count: w * h * 4)
        var b = [Float](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h * 4) {
            a[i] = Float(image.pixels[i]) * (1.0 / 255.0)
        }

        for _ in 0..<glassBlurIterations {
            horizontalBlurPass(a, &b, w: w, h: h, step: spread)
            verticalBlurPass(b, &a, w: w, h: h, step: spread)
        }

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<pixels.count {
            let v = a[i] * 255.0 + 0.5
            pixels[i] = UInt8(min(max(v, 0), 255))
        }
        return RGBAImage(width: w, height: h, pixels: pixels)
    }

    private static let blurOffsets: [Int] = [0, 1, -1, 2, -2, 3, -3, 4, -4]
    private static let blurWeights: [Double] = [
        0.227027,
        0.194594, 0.194594,
        0.121622, 0.121622,
        0.054054, 0.054054,
        0.016216, 0.016216,
    ]

    /// Horizontal pass. Only x is interpolated, so each tap is two fetches.
    private static func horizontalBlurPass(_ src: [Float], _ dst: inout [Float], w: Int, h: Int, step: Double) {
        let offsets = blurOffsets
        let weights = blurWeights
        src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                for y in 0..<h {
                    let row = y * w * 4
                    for x in 0..<w {
                        var acc0 = 0.0, acc1 = 0.0, acc2 = 0.0, acc3 = 0.0
                        for k in 0..<offsets.count {
                            let weight = weights[k]
                            let sx = Double(x) + 0.5 + Double(offsets[k]) * step
                            let fx = sx - 0.5
                            let x0raw = fx.rounded(.down)
                            let tx = fx - x0raw
                            let x0 = min(max(Int(x0raw), 0), w - 1)
                            let x1 = min(max(Int(x0raw) + 1, 0), w - 1)
                            let i0 = row + x0 * 4
                            let i1 = row + x1 * 4
                            let w0 = (1 - tx) * weight
                            let w1 = tx * weight
                            acc0 += Double(s[i0]) * w0 + Double(s[i1]) * w1
                            acc1 += Double(s[i0 + 1]) * w0 + Double(s[i1 + 1]) * w1
                            acc2 += Double(s[i0 + 2]) * w0 + Double(s[i1 + 2]) * w1
                            acc3 += Double(s[i0 + 3]) * w0 + Double(s[i1 + 3]) * w1
                        }
                        let o = row + x * 4
                        d[o] = Float(acc0)
                        d[o + 1] = Float(acc1)
                        d[o + 2] = Float(acc2)
                        d[o + 3] = Float(acc3)
                    }
                }
            }
        }
    }

    /// Vertical pass. Only y is interpolated, so each tap is two fetches.
    private static func verticalBlurPass(_ src: [Float], _ dst: inout [Float], w: Int, h: Int, step: Double) {
        let offsets = blurOffsets
        let weights = blurWeights
        src.withUnsafeBufferPointer { s in
            dst.withUnsafeMutableBufferPointer { d in
                for y in 0..<h {
                    let row = y * w * 4
                    for x in 0..<w {
                        var acc0 = 0.0, acc1 = 0.0, acc2 = 0.0, acc3 = 0.0
                        for k in 0..<offsets.count {
                            let weight = weights[k]
                            let sy = Double(y) + 0.5 + Double(offsets[k]) * step
                            let fy = sy - 0.5
                            let y0raw = fy.rounded(.down)
                            let ty = fy - y0raw
                            let y0 = min(max(Int(y0raw), 0), h - 1)
                            let y1 = min(max(Int(y0raw) + 1, 0), h - 1)
                            let i0 = (y0 * w + x) * 4
                            let i1 = (y1 * w + x) * 4
                            let w0 = (1 - ty) * weight
                            let w1 = ty * weight
                            acc0 += Double(s[i0]) * w0 + Double(s[i1]) * w1
                            acc1 += Double(s[i0 + 1]) * w0 + Double(s[i1 + 1]) * w1
                            acc2 += Double(s[i0 + 2]) * w0 + Double(s[i1 + 2]) * w1
                            acc3 += Double(s[i0 + 3]) * w0 + Double(s[i1 + 3]) * w1
                        }
                        let o = row + x * 4
                        d[o] = Float(acc0)
                        d[o + 1] = Float(acc1)
                        d[o + 2] = Float(acc2)
                        d[o + 3] = Float(acc3)
                    }
                }
            }
        }
    }

    /// Shade one glass panel.
    ///
    /// - Parameters:
    ///   - config: the resolved optics for this panel.
    ///   - size: the panel's CSS box size in points (the bevel is inset from
    ///     this box; the backdrop is larger by `2 * glassShadowPad`).
    ///   - scale: device pixel ratio. All lengths are converted to device
    ///     pixels internally, exactly as the reference does.
    /// - Returns: an image the size of the backdrop, ready to composite over
    ///   the scene at the panel's padded origin.
    public func renderPanel(config: GlassConfig, size: LGSize, scale: Double = 1) -> RGBAImage {
        guard backdrop.width > 0, backdrop.height > 0, size.width > 0, size.height > 0 else {
            return RGBAImage(width: 0, height: 0)
        }

        // A 1x1 backdrop is a flat colour stand-in: the `.color` backdrop, or
        // the black backdrop used when the lighting is composited over the
        // system blur. The panel's geometry comes from `size` and `scale`, so
        // the stand-in is expanded to the padded box before sampling. Sampling
        // a 1x1 image directly would run the whole loop over a single pixel and
        // collapse the rim and specular gradient to one flat value.
        let source: RGBAImage
        if backdrop.width == 1 && backdrop.height == 1 {
            let boxW = Int(((size.width + glassShadowPad * 2) * scale).rounded())
            let boxH = Int(((size.height + glassShadowPad * 2) * scale).rounded())
            source = RGBAImage(width: max(boxW, 1), height: max(boxH, 1), fill: backdrop.color(x: 0, y: 0))
        } else {
            source = backdrop
        }

        let w = source.width
        let h = source.height
        var out = RGBAImage(width: w, height: h)
        let blurred = Self.blur(source, amount: config.blurAmount)

        let dpr = scale
        let panelW = size.width * dpr
        let panelH = size.height * dpr
        let half = LGPoint(x: panelW / 2, y: panelH / 2)
        let radius = min(config.cornerRadius * dpr, min(half.x, half.y))
        let zRadius = config.zRadius * dpr
        let pad = glassShadowPad * dpr
        let shadowSpread = config.shadowSpread * dpr
        let shadowOffY = config.shadowOffsetY * dpr

        // The panel quad covers the padded box; the panel itself is centred.
        let total = LGPoint(x: panelW + pad * 2, y: panelH + pad * 2)
        // Texture coordinates: one texel step in screen space.
        let pxToUV = LGPoint(x: 1 / Double(w), y: -1 / Double(h))
        let absPxToUV = LGPoint(x: 1 / Double(w), y: 1 / Double(h))

        let maxD = min(half.x, half.y)

        for py in 0..<h {
            for px in 0..<w {
                // Local panel coordinates in device pixels, origin at the
                // panel centre. `a_pos` in the shader spans [-0.5, 0.5].
                let localX = (Double(px) + 0.5) / Double(w) * total.x - total.x / 2
                let localY = (Double(py) + 0.5) / Double(h) * total.y - total.y / 2
                let local = LGPoint(x: localX, y: localY)

                let sdf = GlassMath.roundedRectSDF(local, halfExtent: half, radius: radius)

                // Screen UV for this fragment, matching the vertex shader's
                // mapping (y flipped because the backdrop is top-left origin).
                let screenU = (Double(px) + 0.5) / Double(w)
                let screenV = 1 - (Double(py) + 0.5) / Double(h)

                if sdf > 0 {
                    // Outside the panel: only the drop shadow is emitted.
                    let shadowSDF = GlassMath.roundedRectSDF(
                        LGPoint(x: local.x, y: local.y - shadowOffY),
                        halfExtent: half,
                        radius: radius
                    )
                    let d = max(shadowSDF - 1, 0)
                    let spread = max(shadowSpread, 1)
                    let falloff = 1 / (spread * spread)
                    let outerShadow = exp(-d * d * falloff) * 0.65
                    let contactShadow = exp(-d * 0.08 / max(spread * 0.04, 0.01)) * 0.35
                    let shadow = (outerShadow + contactShadow) * config.shadowOpacity
                    out.setColor(x: px, y: py, RGBAColor(r: 0, g: 0, b: 0, a: shadow))
                    continue
                }

                let mask = 1 - GlassMath.smoothstep(-1.5, 0.5, sdf)
                let inside = -sdf
                let edge = GlassMath.smoothstep(maxD * 0.35, 0, inside)

                let surface = GlassMath.surfaceSample(
                    localPx: local,
                    halfExtent: half,
                    radius: radius,
                    zRadius: zRadius
                )
                let normal = surface.normal
                let depth = GlassMath.smoothstep(0, zRadius, inside)

                let refrPx = GlassMath.refractionOffset(
                    localPx: local,
                    halfExtent: half,
                    zRadius: zRadius,
                    refraction: config.refraction,
                    bevelMode: config.bevelMode,
                    height: surface.height,
                    gradient: surface.gradient,
                    distanceInside: surface.distanceInside
                )
                let refr = LGPoint(x: refrPx.x * pxToUV.x, y: refrPx.y * pxToUV.y)

                let ns = LGPoint(x: local.x * 0.08, y: local.y * 0.08)
                let microX = (GlassMath.hash(ns) - 0.5) * config.distortion * 4 * absPxToUV.x
                let microY = (GlassMath.hash(LGPoint(x: ns.x + 37, y: ns.y)) - 0.5) * config.distortion * 4 * absPxToUV.y

                let caS = config.chromAberration * 18 * (edge * 0.7 + 0.3) * 2
                let caX = normal.x * caS * pxToUV.x
                let caY = normal.y * caS * pxToUV.y

                let baseU = screenU + refr.x + microX
                let baseV = screenV + refr.y + microY

                // Shader texture lookups use UV with y-up; our image is y-down.
                @inline(__always) func fetch(_ image: RGBAImage, _ u: Double, _ v: Double) -> RGBAColor {
                    image.sampleBilinear(x: u * Double(w), y: (1 - v) * Double(h))
                }

                let sharp = RGBAColor(
                    r: fetch(source, baseU + caX, baseV + caY).r,
                    g: fetch(source, baseU, baseV).g,
                    b: fetch(source, baseU - caX, baseV - caY).b,
                    a: 1
                )
                let blurSample = RGBAColor(
                    r: fetch(blurred, baseU + caX, baseV + caY).r,
                    g: fetch(blurred, baseU, baseV).g,
                    b: fetch(blurred, baseU - caX, baseV - caY).b,
                    a: 1
                )

                let edgeMix = 1 - edge * 0.15
                var col = sharp.mixed(with: blurSample, amount: edgeMix)

                col = RGBAColor(
                    r: col.r * (1 + config.brightness),
                    g: col.g * (1 + config.brightness),
                    b: col.b * (1 + config.brightness),
                    a: 1
                )

                let lum = col.r * 0.299 + col.g * 0.587 + col.b * 0.114
                let satK = 1 + config.saturation
                col = RGBAColor(
                    r: lum + (col.r - lum) * satK,
                    g: lum + (col.g - lum) * satK,
                    b: lum + (col.b - lum) * satK,
                    a: 1
                )

                // Cool blue glass tint.
                let tintedR = col.r * 0.92
                let tintedG = col.g * 0.95
                let tintedB = col.b * 1.05
                col = RGBAColor(
                    r: col.r + (tintedR - col.r) * config.tintStrength,
                    g: col.g + (tintedG - col.g) * config.tintStrength,
                    b: col.b + (tintedB - col.b) * config.tintStrength,
                    a: 1
                )

                let depthGain = 1 + 0.06 * depth
                col = RGBAColor(r: col.r * depthGain, g: col.g * depthGain, b: col.b * depthGain, a: 1)

                if let tint = config.tintColor {
                    col = RGBAColor(
                        r: col.r + (tint.r - col.r) * config.tintStrength,
                        g: col.g + (tint.g - col.g) * config.tintStrength,
                        b: col.b + (tint.b - col.b) * config.tintStrength,
                        a: 1
                    )
                }

                // Fresnel.
                let fres = pow(1 - abs(normal.z), 4) * config.fresnel

                // Multi-light Blinn-Phong specular.
                let spec = specularTerm(normal: normal) * config.specular

                // Inner stroke.
                let borderWidth = 1.5
                var innerStroke = GlassMath.smoothstep(-borderWidth - 1, -borderWidth, sdf)
                    * (1 - GlassMath.smoothstep(-1, 0, sdf))
                let topBias = 0.5 + 0.5 * (-local.y / max(half.y, 1))
                innerStroke *= (0.4 + 0.6 * topBias)

                let rim = edge * config.edgeHighlight * 0.22
                let innerGlow = GlassMath.smoothstep(5, 0, inside) * config.edgeHighlight * 0.15
                let envRefl = (normal.y * 0.5 + 0.5) * fres * 0.08

                var fin = col
                fin.r += spec + rim + innerGlow + innerStroke * config.edgeHighlight * 0.55 + envRefl
                fin.g += spec + rim + innerGlow + innerStroke * config.edgeHighlight * 0.55 + envRefl
                fin.b += spec + rim + innerGlow + innerStroke * config.edgeHighlight * 0.55 + envRefl

                let fresnelWhite = fres * 0.2
                fin = RGBAColor(
                    r: fin.r + (1 - fin.r) * fresnelWhite,
                    g: fin.g + (1 - fin.g) * fresnelWhite,
                    b: fin.b + (1 - fin.b) * fresnelWhite,
                    a: 1
                )

                let alpha = mask * config.opacity
                out.setColor(x: px, y: py, RGBAColor(r: fin.r, g: fin.g, b: fin.b, a: alpha))
            }
        }
        return out
    }

    /// The four-light specular sum from the shader.
    ///
    /// Three of the four are Blinn-Phong (`dot(N, H)` with `H = normalize(L + V)`
    /// and `V = (0, 0, 1)`); the broad fill light uses `dot(N, L)` directly,
    /// matching the reference GLSL.
    private func specularTerm(normal: (x: Double, y: Double, z: Double)) -> Double {
        @inline(__always) func blinn(_ l: (Double, Double, Double), _ exponent: Double) -> Double {
            let len = (l.0 * l.0 + l.1 * l.1 + l.2 * l.2).squareRoot()
            let lx = l.0 / len, ly = l.1 / len, lz = l.2 / len
            let hx = lx, hy = ly, hz = lz + 1
            let hlen = (hx * hx + hy * hy + hz * hz).squareRoot()
            let dot = normal.x * (hx / hlen) + normal.y * (hy / hlen) + normal.z * (hz / hlen)
            return pow(max(dot, 0), exponent)
        }
        @inline(__always) func lambert(_ l: (Double, Double, Double), _ exponent: Double) -> Double {
            let len = (l.0 * l.0 + l.1 * l.1 + l.2 * l.2).squareRoot()
            let dot = normal.x * (l.0 / len) + normal.y * (l.1 / len) + normal.z * (l.2 / len)
            return pow(max(dot, 0), exponent)
        }
        let sp1 = blinn((0.4, 0.7, 1.0), 90)
        let sp2 = blinn((-0.3, -0.5, 1.0), 50) * 0.3
        let spB = lambert((0.1, 0.3, 1.0), 6) * 0.1
        let sp4 = blinn((0.0, 0.9, 0.4), 120) * 0.6
        return sp1 + sp2 + spB + sp4
    }
}
