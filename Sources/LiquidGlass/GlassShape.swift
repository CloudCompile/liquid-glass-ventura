#if os(macOS)
import SwiftUI
import LiquidGlassCore

/// A shape a glass surface can take.
///
/// The port needs the corner radius as a number, because the optical model
/// derives its bevel from a rounded-rectangle signed distance field. Rather
/// than try to reverse-engineer an arbitrary `Shape`, callers pick one of these
/// and the radius is passed straight through.
public enum GlassShape: Equatable, Sendable {
    case capsule
    case rect(cornerRadius: Double)
    case circle

    /// The corner radius to hand the optical model for a given box size.
    public func cornerRadius(for size: LGSize) -> Double {
        switch self {
        case .capsule:
            return min(size.width, size.height) / 2
        case .rect(let radius):
            return radius
        case .circle:
            return min(size.width, size.height) / 2
        }
    }

    /// The outline as a `CGPath`, for masking native layers.
    public func path(in rect: CGRect) -> CGPath {
        switch self {
        case .capsule:
            return CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .rect(let radius):
            let clamped = min(CGFloat(radius), min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: clamped, cornerHeight: clamped, transform: nil)
        }
    }
}

/// The default shape, matching Apple's `DefaultGlassEffectShape`.
public typealias DefaultGlassEffectShape = Capsule
#endif
