#if os(macOS)
import SwiftUI
import LiquidGlassCore

/// The three material variants, matching Apple's `Glass` type.
///
/// On macOS 26 and later the modifier this is passed to forwards to the real
/// `.glassEffect`, so the same call site produces the system material there and
/// the ported optical model on Ventura through macOS 15.
public struct LiquidGlassMaterial: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case regular
        case clear
        case identity
    }

    var kind: Kind
    var tintColor: RGBColor?
    var isInteractive: Bool

    /// The default material: adaptive, tinted by the system, interactive only
    /// where the caller asks for it.
    public static let regular = LiquidGlassMaterial(kind: .regular)

    /// A highly transparent material for controls floating over media.
    public static let clear = LiquidGlassMaterial(kind: .clear)

    /// No material at all. Use it to switch the effect off conditionally.
    public static let identity = LiquidGlassMaterial(kind: .identity)

    /// Apply a colour tint. Repeated calls replace the previous tint.
    public func tint(_ color: Color) -> LiquidGlassMaterial {
        var copy = self
        copy.tintColor = RGBColor(color)
        return copy
    }

    /// Make the surface respond to the pointer: it brightens on hover and
    /// flattens on press.
    public func interactive(_ enabled: Bool = true) -> LiquidGlassMaterial {
        var copy = self
        copy.isInteractive = enabled
        return copy
    }

    public var isEnabled: Bool { kind != .identity }

    /// The optics this material maps to.
    ///
    /// `.regular` and `.clear` differ mainly in how much of the backdrop shows
    /// through: `.clear` refracts harder and blurs less, so media stays legible
    /// behind it. The `prominence` argument comes from the button styles, where
    /// a prominent action gets a stronger tint.
    func config(prominence: Double = 0, tintOverride: RGBColor? = nil) -> GlassConfig {
        var config: GlassConfig
        switch kind {
        case .regular:
            config = .materialRegular
        case .clear:
            config = .materialClear
        case .identity:
            config = GlassConfig(blurAmount: 0, refraction: 0, cornerRadius: 0, zRadius: 0, shadowOpacity: 0)
        }
        config.button = isInteractive

        if prominence > 0 {
            config.tintColor = config.tintColor ?? GlassConfig.accentColor
            config.tintStrength = 0.45
            config.shadowOpacity = min(config.shadowOpacity + 0.08 * prominence, 0.5)
        }
        if let tint = tintOverride ?? tintColor {
            config.tintColor = tint
            // A tint is only visible if the tint term is doing something.
            config.tintStrength = max(config.tintStrength, 0.45)
        }
        return config
    }
}

extension RGBColor {
    /// Convert a SwiftUI colour to the core's sRGB triplet.
    ///
    /// `Color` can hold any colour space, so it is resolved through `NSColor`
    /// first; a colour that cannot be converted falls back to opaque black
    /// rather than failing.
    init(_ color: Color) {
        let ns = NSColor(color)
        guard let srgb = ns.usingColorSpace(.sRGB) else {
            self = .black
            return
        }
        self.init(
            r: Double(srgb.redComponent),
            g: Double(srgb.greenComponent),
            b: Double(srgb.blueComponent)
        )
    }
}
#endif
