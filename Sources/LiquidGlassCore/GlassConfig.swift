import Foundation

/// How the bevel's cross-section is modelled.
///
/// Both modes share the same half-circle height profile. They differ in how
/// light is assumed to travel through the panel.
public enum GlassBevelMode: Int, CaseIterable, Sendable {
    /// Light refracts at both surfaces (entry and exit). The default pill.
    case biconvex = 0

    /// Flat bottom, curved top — a plano-convex dome. Pair with
    /// `cornerRadius == zRadius` for a half-sphere magnifier.
    case dome = 1
}

/// The optical and behavioural parameters of a single glass surface.
///
/// This is a one-to-one port of the reference web library's `GlassConfig`,
/// so a config authored for the web port produces the same optics here.
public struct GlassConfig: Equatable, Sendable {
    /// Background blur strength. `0` is sharp, `1` is maximum blur.
    public var blurAmount: Double
    /// Refraction strength — how much the glass bends the image behind it.
    public var refraction: Double
    /// Chromatic aberration — colour fringing at the edges.
    public var chromAberration: Double
    /// Edge highlight intensity (inner rim lighting).
    public var edgeHighlight: Double
    /// Specular highlight intensity (multi-light Blinn-Phong).
    public var specular: Double
    /// Fresnel reflection intensity at grazing angles.
    public var fresnel: Double
    /// Micro-distortion noise strength.
    public var distortion: Double
    /// Corner radius in points.
    public var cornerRadius: Double
    /// Bevel depth — the curvature of the panel's cross-section.
    public var zRadius: Double
    /// Overall opacity of the glass panel.
    public var opacity: Double
    /// Saturation adjustment. `-1` desaturates, `0` is neutral, `1` is vivid.
    public var saturation: Double
    /// Cool blue glass tint strength.
    public var tintStrength: Double
    /// Brightness adjustment, nominally in `-0.5 ... 0.5`.
    public var brightness: Double
    /// Drop shadow opacity. `0` disables the shadow.
    public var shadowOpacity: Double
    /// Drop shadow spread in points.
    public var shadowSpread: Double
    /// Drop shadow vertical offset in points.
    public var shadowOffsetY: Double
    /// Allow the surface to be dragged around.
    public var floating: Bool
    /// Treat the surface as a button: hover brightens, press flattens.
    public var button: Bool
    /// Bevel cross-section model.
    public var bevelMode: GlassBevelMode
    /// Optional colour tint applied on top of the cool-glass tint, as a
    /// straight (non-premultiplied) sRGB triplet in `0 ... 1`.
    public var tintColor: RGBColor?
    /// Composite the panel the way the reference library does on screen.
    ///
    /// The web library shades into a WebGL canvas with
    /// `blendFunc(SRC_ALPHA, ONE_MINUS_SRC_ALPHA)` and an alpha channel.
    /// Measured against the live library, that stores `rgb * alpha` and
    /// `alpha²`, so the browser ends up compositing the panel as
    /// `rgb * alpha + backdrop * (1 - alpha²)`.
    ///
    /// `true` (the default) reproduces that exactly, so a translucent panel
    /// matches the reference. Set `false` for textbook straight-alpha
    /// source-over, which makes translucent panels read slightly more solid.
    public var referenceAlphaCompositing: Bool

    public init(
        blurAmount: Double = 0,
        refraction: Double = 0.69,
        chromAberration: Double = 0.05,
        edgeHighlight: Double = 0.05,
        specular: Double = 0,
        fresnel: Double = 1,
        distortion: Double = 0,
        cornerRadius: Double = 65,
        zRadius: Double = 40,
        opacity: Double = 1,
        saturation: Double = 0,
        tintStrength: Double = 0,
        brightness: Double = 0,
        shadowOpacity: Double = 0.30,
        shadowSpread: Double = 10,
        shadowOffsetY: Double = 1,
        floating: Bool = false,
        button: Bool = false,
        bevelMode: GlassBevelMode = .biconvex,
        tintColor: RGBColor? = nil,
        referenceAlphaCompositing: Bool = true
    ) {
        self.blurAmount = blurAmount
        self.refraction = refraction
        self.chromAberration = chromAberration
        self.edgeHighlight = edgeHighlight
        self.specular = specular
        self.fresnel = fresnel
        self.distortion = distortion
        self.cornerRadius = cornerRadius
        self.zRadius = zRadius
        self.opacity = opacity
        self.saturation = saturation
        self.tintStrength = tintStrength
        self.brightness = brightness
        self.shadowOpacity = shadowOpacity
        self.shadowSpread = shadowSpread
        self.shadowOffsetY = shadowOffsetY
        self.floating = floating
        self.button = button
        self.bevelMode = bevelMode
        self.tintColor = tintColor
        self.referenceAlphaCompositing = referenceAlphaCompositing
    }

    /// The library defaults, matching the web reference exactly.
    public static let standard = GlassConfig()

    // The material presets live here rather than in the Apple layer so the
    // render tool can produce a faithful preview of the SwiftUI surface set on
    // any platform. `LiquidGlassMaterial` reads these directly.

    /// The `.regular` material: an adaptive control surface.
    public static let materialRegular = GlassConfig(
        blurAmount: 0.30,
        refraction: 0.62,
        chromAberration: 0.05,
        edgeHighlight: 0.08,
        specular: 0.35,
        fresnel: 0.7,
        distortion: 0.02,
        cornerRadius: 18,
        zRadius: 24,
        tintStrength: 0.06,
        shadowOpacity: 0.22,
        shadowSpread: 14,
        shadowOffsetY: 3
    )

    /// The `.clear` material: a highly transparent surface for media.
    public static let materialClear = GlassConfig(
        blurAmount: 0.10,
        refraction: 0.50,
        chromAberration: 0.08,
        edgeHighlight: 0.12,
        specular: 0.5,
        fresnel: 0.9,
        distortion: 0.03,
        cornerRadius: 18,
        zRadius: 24,
        opacity: 0.72,
        tintStrength: 0.02,
        shadowOpacity: 0.18,
        shadowSpread: 10,
        shadowOffsetY: 2
    )

    /// The macOS accent blue, used by the prominent button style.
    public static let accentColor = RGBColor(r: 0.04, g: 0.52, b: 1.0)

    /// A control surface, sized for a button or a circular icon button.
    public static func materialButton(prominent: Bool = false, clear: Bool = false, circle: Bool = false) -> GlassConfig {
        var config = clear ? materialClear : materialRegular
        if prominent {
            // A prominent action is tinted with the accent colour, matching
            // `Glass.tint(.accentColor)` on the system API.
            config.tintColor = accentColor
            config.tintStrength = 0.45
            config.shadowOpacity = min(config.shadowOpacity + 0.08, 0.5)
        }
        config.button = true
        if circle {
            // A circle's corner radius is half its box, so a fixed radius only
            // looks right once the size is known; the Apple layer overrides it.
            config.cornerRadius = 29
            config.zRadius = 20
        }
        return config
    }

    /// A subtle surface for menus and sidebars: less refraction, more blur.
    public static let panel = GlassConfig(
        blurAmount: 0.28,
        refraction: 0.42,
        cornerRadius: 20,
        zRadius: 18,
        shadowOpacity: 0.22,
        shadowSpread: 14,
        shadowOffsetY: 4
    )

    /// A thin, crisp surface for toolbar chips.
    public static let chip = GlassConfig(
        blurAmount: 0.12,
        refraction: 0.30,
        edgeHighlight: 0.10,
        cornerRadius: 18,
        zRadius: 14,
        shadowOpacity: 0.18,
        shadowSpread: 8
    )

    /// A half-sphere magnifier. Note `cornerRadius == zRadius`.
    public static let magnifier = GlassConfig(
        refraction: 0.9,
        cornerRadius: 60,
        zRadius: 60,
        shadowOpacity: 0.35,
        shadowSpread: 16,
        bevelMode: .dome
    )

    /// Merge: values from `other` win when they differ from the standard
    /// defaults. Mirrors the web library's `{ ...defaults, ...perElement }`
    /// spread where a per-element JSON blob overrides the instance defaults.
    public func overriding(with other: GlassConfig) -> GlassConfig {
        var merged = self
        let base = GlassConfig.standard
        func take<T: Equatable>(_ keyPath: WritableKeyPath<GlassConfig, T>) {
            if other[keyPath: keyPath] != base[keyPath: keyPath] {
                merged[keyPath: keyPath] = other[keyPath: keyPath]
            }
        }
        take(\.blurAmount)
        take(\.refraction)
        take(\.chromAberration)
        take(\.edgeHighlight)
        take(\.specular)
        take(\.fresnel)
        take(\.distortion)
        take(\.cornerRadius)
        take(\.zRadius)
        take(\.opacity)
        take(\.saturation)
        take(\.tintStrength)
        take(\.brightness)
        take(\.shadowOpacity)
        take(\.shadowSpread)
        take(\.shadowOffsetY)
        take(\.floating)
        take(\.button)
        take(\.bevelMode)
        take(\.referenceAlphaCompositing)
        if other.tintColor != nil { merged.tintColor = other.tintColor }
        return merged
    }

    /// Apply a button's hover/press state, exactly as the web reference does:
    /// pressing flattens the bevel by 20% and widens the shadow by 20%;
    /// hovering lifts brightness by 0.2.
    public func applyingButtonState(hovered: Bool, pressed: Bool) -> GlassConfig {
        guard button else { return self }
        var c = self
        if pressed {
            c.zRadius *= 0.8
            c.shadowSpread *= 1.2
        } else if hovered {
            c.brightness += 0.2
        }
        return c
    }
}

/// Number of Gaussian blur passes. Higher is smoother and slower.
public let glassBlurIterations = 6

/// Extra padding around each panel when rendering its drop shadow, in points.
public let glassShadowPad: Double = 20
