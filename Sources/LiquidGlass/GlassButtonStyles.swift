#if os(macOS)
import SwiftUI

/// The glass button style, available on every macOS from Ventura.
///
/// On macOS 26 and later the body forwards to the system's own glass effect;
/// earlier systems get the ported interactive glass surface, which brightens on
/// hover and flattens on press.
///
/// The style is spelled `.liquidGlass` rather than `.glass` on purpose. Apple's
/// `.glass` and `.glassProminent` already exist on macOS 26, and declaring the
/// same names on the same protocol would make `.buttonStyle(.glass)` ambiguous
/// for anyone building against that SDK. The typed constants below keep the
/// Apple spelling reachable when it is wanted explicitly.
///
/// ```swift
/// Button("Confirm") {}.buttonStyle(.liquidGlassProminent)
/// Button("Cancel") {}.buttonStyle(LiquidGlassButtonStyle.glass)
/// ```
public struct LiquidGlassButtonStyle: ButtonStyle {
    enum Prominence {
        case regular
        case prominent
        case clear
    }

    let prominence: Prominence

    /// The standard glass button, matching Apple's `.glass`.
    public static var glass: LiquidGlassButtonStyle { LiquidGlassButtonStyle(prominence: .regular) }

    /// The primary-action button, matching Apple's `.glassProminent`.
    public static var glassProminent: LiquidGlassButtonStyle { LiquidGlassButtonStyle(prominence: .prominent) }

    /// A transparent button for controls floating over media.
    public static var glassClear: LiquidGlassButtonStyle { LiquidGlassButtonStyle(prominence: .clear) }

    public func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, prominence: prominence)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: LiquidGlassButtonStyle.Prominence

    private var material: LiquidGlassMaterial {
        switch prominence {
        case .regular: return .regular
        case .prominent: return .regular.tint(.accentColor)
        case .clear: return .clear
        }
    }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // The system material already handles press, hover, and focus.
            configuration.label
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(nativeGlass, in: .capsule)
        } else {
            ported
        }
        #else
        ported
        #endif
    }

    /// The ported button, used on Ventura through macOS 15 and on any toolchain
    /// older than Xcode 26.
    private var ported: some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Capsule())
            .liquidGlass(material.interactive(), in: .capsule)
            // The ported model darkens on press, but a small scale change
            // matches the system's feel.
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var nativeGlass: Glass {
        switch prominence {
        case .regular: return .regular.interactive()
        case .prominent: return .regular.tint(.accentColor).interactive()
        case .clear: return .clear.interactive()
        }
    }
    #endif
}

public extension ButtonStyle where Self == LiquidGlassButtonStyle {
    /// The standard glass button style, on every macOS from Ventura.
    static var liquidGlass: LiquidGlassButtonStyle { .glass }

    /// The prominent glass button style, for the primary action in a view.
    static var liquidGlassProminent: LiquidGlassButtonStyle { .glassProminent }

    /// A transparent glass button style for controls over media.
    static var liquidGlassClear: LiquidGlassButtonStyle { .glassClear }
}
#endif
