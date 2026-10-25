#if os(macOS)
import SwiftUI

public extension View {
    /// Give a glass surface a stable identity so it can morph when the view
    /// hierarchy changes.
    ///
    /// On macOS 26 and later this is the system `glassEffectID`. Earlier
    /// systems have no materialise transition to drive, so the modifier returns
    /// the view unchanged; use `withAnimation` around your own state change if
    /// you want a cross-fade.
    @ViewBuilder
    func liquidGlassID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Merge surfaces that share a union id into a single shape.
    ///
    /// The system implements this on macOS 26 and later. Earlier systems have
    /// no union id, so this returns the view unchanged — use
    /// `GlassEffectContainer`, which does the merging itself on those systems.
    @ViewBuilder
    func liquidGlassUnion<ID: Hashable>(id: ID, namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffectUnion(id: id, namespace: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// The transition used when a glass surface appears or disappears.
    ///
    /// On macOS 26 and later this is the system `glassEffectTransition`. Earlier
    /// systems have no materialise transition, so the view is returned unchanged.
    @ViewBuilder
    func liquidGlassTransition(_ transition: LiquidGlassTransition) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            switch transition {
            case .matchedGeometry:
                self.glassEffectTransition(.matchedGeometry)
            case .materialize:
                self.glassEffectTransition(.materialize)
            case .identity:
                self.glassEffectTransition(.identity)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// The transitions a glass surface can use when it appears or disappears,
/// mirroring Apple's `GlassEffectTransition`.
public enum LiquidGlassTransition: Sendable {
    /// Blend geometry with another surface that shares an id.
    case matchedGeometry
    /// Fade the material in or out.
    case materialize
    /// No transition.
    case identity
}
#endif
