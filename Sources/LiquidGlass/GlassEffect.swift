#if os(macOS)
import SwiftUI
import LiquidGlassCore

/// Attach a glass surface behind this view's content.
///
/// The same call site behaves correctly on every macOS from Ventura up:
///
/// - On macOS 26 and later it forwards to the system `.glassEffect`, so apps
///   get the real material, the system's motion response, and its accessibility
///   behaviour for free.
/// - On macOS 13 through 15 it renders the ported optical model — the same
///   refraction, chromatic dispersion, and specular shading the reference web
///   library produces.
///
/// ```swift
/// Text("Hello")
///     .padding()
///     .liquidGlass(.regular.interactive(), in: .rect(cornerRadius: 16))
/// ```
///
/// - Parameters:
///   - material: the surface variant and its tint/interactivity.
///   - shape: the outline the bevel follows. The default is a capsule.
///   - isEnabled: set `false` to skip the effect entirely, matching the
///     `isEnabled` parameter of the system API.
public struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let material: LiquidGlassMaterial
    let shape: GlassShape
    let swiftUIShape: S
    let backdrop: GlassBackdrop
    let config: GlassConfig?
    let isEnabled: Bool

    public func body(content: Content) -> some View {
        if !isEnabled || !material.isEnabled {
            content
        } else {
            GlassEffectBody(
                content: content,
                material: material,
                shape: shape,
                swiftUIShape: swiftUIShape,
                backdrop: backdrop,
                config: config
            )
        }
    }
}

/// Whether an enclosing `GlassEffectContainer` has taken over drawing the
/// surface, so this modifier must not draw its own.
struct LiquidGlassContainerActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var liquidGlassContainerActive: Bool {
        get { self[LiquidGlassContainerActiveKey.self] }
        set { self[LiquidGlassContainerActiveKey.self] = newValue }
    }
}

/// Reports a glass surface's geometry and optics to an enclosing
/// `GlassEffectContainer`, which draws the merged panel for the whole group.
///
/// The reported frame is the surface's own box, so the container can cluster by
/// proximity without knowing anything else about the hierarchy. It uses the
/// container's named coordinate space, which the container establishes around
/// itself.
struct GlassRegistryReporter: View {
    let config: GlassConfig
    let backdrop: GlassBackdrop

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .named("liquidGlassContainer"))
            Color.clear.preference(
                key: GlassSurfaceRegistryKey.self,
                value: [GlassSurfaceRegistration(frame: frame, config: config, backdrop: backdrop)]
            )
        }
    }
}

/// Splits the availability check out of `body` so both branches compile on the
/// same SDK, which keeps the Ventura floor working while still calling the
/// native API where it exists.
private struct GlassEffectBody<S: Shape, Content: View>: View {
    let content: Content
    let material: LiquidGlassMaterial
    let shape: GlassShape
    let swiftUIShape: S
    let backdrop: GlassBackdrop
    let config: GlassConfig?

    @Environment(\.liquidGlassContainerActive) private var inContainer

    var body: some View {
        #if compiler(>=6.2)
        // The system material only exists in the SDK that ships with Xcode 26,
        // so the call is compiled out entirely on older toolchains. Building
        // against an older SDK is the normal case on Ventura and macOS 14/15,
        // and it must still work.
        if #available(macOS 26.0, *) {
            // A raw config only exists to drive the ported model, so the native
            // path uses the closest material variant instead.
            content.glassEffect(nativeGlass, in: swiftUIShape)
        } else {
            ported
        }
        #else
        ported
        #endif
    }

    /// The ported optical model, used whenever the system material is not
    /// available — either at runtime or at compile time.
    @ViewBuilder
    private var ported: some View {
        // Inside a container the group is drawn as one merged panel, so this
        // modifier only reports where the surface is and draws nothing.
        let resolved = config ?? material.config()
        content
            .background {
                if !inContainer {
                    GlassSurfaceView(
                        material: material,
                        shape: shape,
                        prominence: 0,
                        backdrop: backdrop,
                        configOverride: config
                    )
                }
            }
            .background {
                if inContainer {
                    GlassRegistryReporter(config: resolved, backdrop: backdrop)
                }
            }
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var nativeGlass: Glass {
        var glass: Glass
        switch material.kind {
        case .regular: glass = .regular
        case .clear: glass = .clear
        case .identity: glass = .identity
        }
        if let tint = material.tintColor {
            glass = glass.tint(Color(red: tint.r, green: tint.g, blue: tint.b))
        }
        if material.isInteractive {
            glass = glass.interactive()
        }
        return glass
    }
    #endif
}

public extension View {
    /// Attach a glass surface behind this view, using the ported optical model
    /// on macOS 13–15 and the system material on macOS 26 and later.
    func liquidGlass(
        _ material: LiquidGlassMaterial = .regular,
        in shape: GlassShape = .capsule,
        backdrop: GlassBackdrop = .nativeBlur,
        isEnabled: Bool = true
    ) -> some View {
        modifier(LiquidGlassModifier(
            material: material,
            shape: shape,
            swiftUIShape: shape.swiftUIShape,
            backdrop: backdrop,
            config: nil,
            isEnabled: isEnabled
        ))
    }

    /// Shape-typed overload matching Apple's signature, for call sites that
    /// already pass a `Shape` value.
    func liquidGlass<S: Shape>(
        _ material: LiquidGlassMaterial = .regular,
        in shape: S,
        backdrop: GlassBackdrop = .nativeBlur,
        isEnabled: Bool = true
    ) -> some View {
        modifier(LiquidGlassModifier(
            material: material,
            shape: shape.glassShape,
            swiftUIShape: shape,
            backdrop: backdrop,
            config: nil,
            isEnabled: isEnabled
        ))
    }

    /// Attach a glass surface driven by a raw `GlassConfig`.
    ///
    /// This is the escape hatch for callers who want to set the optics directly
    /// rather than go through a material variant. On macOS 26 and later the
    /// config cannot be honoured — the system owns the material — so the
    /// nearest variant is used instead.
    func liquidGlass(
        config: GlassConfig,
        in shape: GlassShape = .capsule,
        backdrop: GlassBackdrop = .nativeBlur,
        isEnabled: Bool = true
    ) -> some View {
        modifier(LiquidGlassModifier(
            material: .regular,
            shape: shape,
            swiftUIShape: shape.swiftUIShape,
            backdrop: backdrop,
            config: config,
            isEnabled: isEnabled
        ))
    }
}

extension GlassShape {
    /// The equivalent SwiftUI shape, used for the native path and for clipping.
    var swiftUIShape: AnyShape {
        switch self {
        case .capsule: return AnyShape(Capsule())
        case .circle: return AnyShape(Circle())
        case .rect(let radius): return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

extension Shape {
    /// Best-effort conversion of a SwiftUI shape to the port's shape model.
    ///
    /// Only the shapes the optical model can express are recognised; anything
    /// else falls back to a capsule, which is what the system uses by default.
    var glassShape: GlassShape {
        if self is Capsule { return .capsule }
        if self is Circle { return .circle }
        if let rounded = self as? RoundedRectangle { return .rect(cornerRadius: rounded.cornerRadius) }
        return .capsule
    }
}

/// A type-erased `Shape`, so the shape model can produce one value.
struct AnyShape: Shape {
    private let pathBuilder: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
    }

    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}
#endif
