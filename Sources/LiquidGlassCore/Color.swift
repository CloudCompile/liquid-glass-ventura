import Foundation

/// A straight (non-premultiplied) sRGB colour with components in `0 ... 1`.
public struct RGBColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Build from a 24-bit hex literal, e.g. `RGBColor(hex: 0x2E7DFF)`.
    public init(hex: UInt32) {
        self.r = Double((hex >> 16) & 0xFF) / 255
        self.g = Double((hex >> 8) & 0xFF) / 255
        self.b = Double(hex & 0xFF) / 255
    }

    public static let white = RGBColor(r: 1, g: 1, b: 1)
    public static let black = RGBColor(r: 0, g: 0, b: 0)

    public func scaled(by factor: Double) -> RGBColor {
        RGBColor(r: r * factor, g: g * factor, b: b * factor)
    }

    public func clamped() -> RGBColor {
        RGBColor(
            r: Swift.min(Swift.max(r, 0), 1),
            g: Swift.min(Swift.max(g, 0), 1),
            b: Swift.min(Swift.max(b, 0), 1)
        )
    }

    /// sRGB relative luminance, using the coefficients the reference shader
    /// uses for its saturation step.
    public var luminance: Double {
        0.299 * r + 0.587 * g + 0.114 * b
    }

    /// Linear interpolation towards `other`.
    public func mixed(with other: RGBColor, amount: Double) -> RGBColor {
        let t = Swift.min(Swift.max(amount, 0), 1)
        return RGBColor(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t
        )
    }

    /// Pack into `0xAARRGGBB`, the byte order used by ``RGBAImage``.
    public func packedARGB(alpha: Double) -> UInt32 {
        let a = UInt32(Swift.min(Swift.max(alpha, 0), 1) * 255 + 0.5)
        let ri = UInt32(Swift.min(Swift.max(r, 0), 1) * 255 + 0.5)
        let gi = UInt32(Swift.min(Swift.max(g, 0), 1) * 255 + 0.5)
        let bi = UInt32(Swift.min(Swift.max(b, 0), 1) * 255 + 0.5)
        return (a << 24) | (ri << 16) | (gi << 8) | bi
    }
}

/// An RGBA colour with straight alpha, components in `0 ... 1`.
public struct RGBAColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(_ rgb: RGBColor, alpha: Double = 1) {
        self.init(r: rgb.r, g: rgb.g, b: rgb.b, a: alpha)
    }

    public static let clear = RGBAColor(r: 0, g: 0, b: 0, a: 0)

    /// Linear interpolation towards `other`, alpha included.
    public func mixed(with other: RGBAColor, amount: Double) -> RGBAColor {
        let t = Swift.min(Swift.max(amount, 0), 1)
        return RGBAColor(
            r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t,
            a: a + (other.a - a) * t
        )
    }

    /// Source-over compositing matching the reference library's on-screen
    /// result.
    ///
    /// The web library draws glass into a WebGL canvas with
    /// `blendFunc(SRC_ALPHA, ONE_MINUS_SRC_ALPHA)` on an alpha canvas. Measured
    /// against the live library, that blend stores `rgb * alpha` in the colour
    /// channels and `alpha²` in the alpha channel, so the browser composites the
    /// canvas as `rgb * alpha + backdrop * (1 - alpha²)`.
    ///
    /// Reproducing that here keeps a translucent panel looking exactly like the
    /// reference. Use ``over(_:)`` for textbook straight-alpha compositing.
    public func referenceOver(_ backdrop: RGBAColor) -> RGBAColor {
        let coverage = a * a
        let outA = coverage + backdrop.a * (1 - coverage)
        guard outA > 0 else { return .clear }
        let premultipliedR = r * a + backdrop.r * backdrop.a * (1 - coverage)
        let premultipliedG = g * a + backdrop.g * backdrop.a * (1 - coverage)
        let premultipliedB = b * a + backdrop.b * backdrop.a * (1 - coverage)
        return RGBAColor(
            r: premultipliedR / outA,
            g: premultipliedG / outA,
            b: premultipliedB / outA,
            a: outA
        )
    }

    /// Source-over compositing with straight alpha.
    ///
    /// The reference shader blends the glass canvas over the scene with
    /// `SRC_ALPHA, ONE_MINUS_SRC_ALPHA`, which is exactly this.
    public func over(_ backdrop: RGBAColor) -> RGBAColor {
        let outA = a + backdrop.a * (1 - a)
        guard outA > 0 else { return .clear }
        let outR = (r * a + backdrop.r * backdrop.a * (1 - a)) / outA
        let outG = (g * a + backdrop.g * backdrop.a * (1 - a)) / outA
        let outB = (b * a + backdrop.b * backdrop.a * (1 - a)) / outA
        return RGBAColor(r: outR, g: outG, b: outB, a: outA)
    }
}
