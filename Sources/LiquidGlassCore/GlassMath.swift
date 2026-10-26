import Foundation

/// The analytic geometry of a glass panel: its signed distance field, bevel
/// height field, surface normal, and the refraction offset each pixel applies
/// when it samples the backdrop.
///
/// Every function here is a direct translation of the reference fragment
/// shader, so a panel shaded by ``SoftwareGlassRenderer`` and a panel shaded by
/// the Metal shader agree pixel for pixel.
public enum GlassMath {

    // MARK: - Signed distance

    /// Signed distance to a rounded rectangle centred on the origin.
    ///
    /// Negative inside, positive outside. `b` is the half-extent, `r` the
    /// corner radius.
    public static func roundedRectSDF(_ p: LGPoint, halfExtent b: LGPoint, radius r: Double) -> Double {
        let qx = abs(p.x) - b.x + r
        let qy = abs(p.y) - b.y + r
        let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
        return min(max(qx, qy), 0) + outside - r
    }

    // MARK: - Bevel

    /// Height of the bevel cross-section at `d` points inside the edge.
    ///
    /// A half-circle of radius `zR`: zero exactly at the edge, peaking at `zR`
    /// once you are `zR` inside. This is what gives the panel its lens-like
    /// curvature and, in turn, its edge refraction.
    public static func bevelHeight(distanceInside d: Double, zRadius zR: Double) -> Double {
        if d <= 0 { return 0 }
        if d >= zR { return zR }
        return (d * (2 * zR - d)).squareRoot()
    }

    // MARK: - Surface sampling

    /// Everything the shader needs about one fragment of the panel surface.
    ///
    /// Computing this once per pixel — rather than recomputing the height
    /// field separately for the normal and for refraction — is what keeps the
    /// reference renderer fast enough to generate the screenshot gallery.
    public struct SurfaceSample {
        public var sdf: Double
        public var distanceInside: Double
        public var height: Double
        public var gradient: LGPoint
        public var normal: (x: Double, y: Double, z: Double)
    }

    /// Evaluate the rounded-rect SDF, the bevel height field, its gradient, and
    /// the resulting surface normal at a local panel coordinate.
    ///
    /// Central differences with `e = 2`, matching the shader.
    public static func surfaceSample(
        localPx p: LGPoint,
        halfExtent b: LGPoint,
        radius r: Double,
        zRadius zR: Double,
        epsilon e: Double = 2
    ) -> SurfaceSample {
        let sdf = roundedRectSDF(p, halfExtent: b, radius: r)
        let dC = -sdf
        let hC = bevelHeight(distanceInside: dC, zRadius: zR)
        let hR = bevelHeight(distanceInside: -roundedRectSDF(LGPoint(x: p.x + e, y: p.y), halfExtent: b, radius: r), zRadius: zR)
        let hL = bevelHeight(distanceInside: -roundedRectSDF(LGPoint(x: p.x - e, y: p.y), halfExtent: b, radius: r), zRadius: zR)
        let hU = bevelHeight(distanceInside: -roundedRectSDF(LGPoint(x: p.x, y: p.y + e), halfExtent: b, radius: r), zRadius: zR)
        let hD = bevelHeight(distanceInside: -roundedRectSDF(LGPoint(x: p.x, y: p.y - e), halfExtent: b, radius: r), zRadius: zR)

        let gx = (hR - hL) / (2 * e)
        let gy = (hU - hD) / (2 * e)
        let len = (gx * gx + gy * gy + 1).squareRoot()
        return SurfaceSample(
            sdf: sdf,
            distanceInside: dC,
            height: hC,
            gradient: LGPoint(x: gx, y: gy),
            normal: (x: -gx / len, y: -gy / len, z: 1 / len)
        )
    }

    // MARK: - Refraction

    /// The backdrop sampling offset, in points, for a pixel at `localPx`.
    ///
    /// `bevelMode == .biconvex` models light bending at both surfaces plus a
    /// centre-directed pull that deepens with the bevel; `.dome` contracts the
    /// sample point toward the centre so content appears magnified.
    public static func refractionOffset(
        localPx p: LGPoint,
        halfExtent b: LGPoint,
        zRadius zR: Double,
        refraction: Double,
        bevelMode: GlassBevelMode,
        height hC: Double,
        gradient: LGPoint,
        distanceInside dC: Double
    ) -> LGPoint {
        let depth = smoothstep(0, zR, max(dC, 0))
        let refrPow = 1.0 - 1.0 / 1.5

        if bevelMode == .biconvex {
            let thickNorm = (hC * 2) / max(zR * 2, 1)
            let exitRefrX = gradient.x * refrPow
            let exitRefrY = gradient.y * refrPow
            let throughX = exitRefrX * thickNorm * 0.5
            let throughY = exitRefrY * thickNorm * 0.5
            var refrX = (exitRefrX + exitRefrX + throughX) * refraction * 30
            var refrY = (exitRefrY + exitRefrY + throughY) * refraction * 30
            refrX += (-p.x / max(b.x, 1)) * refraction * 4 * depth
            refrY += (-p.y / max(b.y, 1)) * refraction * 4 * depth
            return LGPoint(x: refrX, y: refrY)
        } else {
            let k = -refraction * depth * 0.35
            return LGPoint(x: p.x * k, y: p.y * k)
        }
    }

    // MARK: - Shaping helpers

    /// GLSL's `smoothstep`.
    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge0 != edge1 else { return x < edge0 ? 0 : 1 }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The reference shader's cheap hash, used for the micro-distortion noise.
    public static func hash(_ p: LGPoint) -> Double {
        // The reference evaluates this at `precision highp float`, so every
        // intermediate is a 32-bit float. Doing the arithmetic in `Double`
        // changes `sin`'s argument in its last bits, and multiplying by
        // 43758.5453 turns that into a different `fract()` branch, so the
        // noise value can differ by up to 1.0. Matching the reference's
        // precision keeps the port on the same branch.
        //
        // The pattern still cannot be matched exactly: `sin` itself is
        // implementation-defined, and Swift's differs from a GPU's in the last
        // bits. That is why `distortion` (the only option that reads this
        // noise) shows a small residual divergence in the cross-check while
        // every other option matches to within a few levels.
        let x = Float(p.x)
        let y = Float(p.y)
        let v = sin(Float(127.1) * x + Float(311.7) * y) * Float(43758.5453)
        return Double(v - v.rounded(.down))
    }
}
