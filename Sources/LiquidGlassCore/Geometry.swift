import Foundation

/// A point in a local, top-left-origin coordinate space.
public struct LGPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = LGPoint(x: 0, y: 0)
}

/// A size in points.
public struct LGSize: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = LGSize(width: 0, height: 0)
}

/// An axis-aligned rectangle in a local, top-left-origin coordinate space.
///
/// The core deliberately avoids `CGRect`/`CGSize` so the optical model and the
/// reference renderer compile unchanged on Linux.
public struct LGRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(origin: LGPoint, size: LGSize) {
        self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    public var origin: LGPoint { LGPoint(x: x, y: y) }
    public var size: LGSize { LGSize(width: width, height: height) }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func intersects(_ other: LGRect) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    public func insetBy(dx: Double, dy: Double) -> LGRect {
        LGRect(x: x + dx, y: y + dy, width: width - 2 * dx, height: height - 2 * dy)
    }

    public func offsetBy(dx: Double, dy: Double) -> LGRect {
        LGRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Grow the rectangle by `pad` on every side. Used for shadow padding.
    public func padded(by pad: Double) -> LGRect {
        LGRect(x: x - pad, y: y - pad, width: width + 2 * pad, height: height + 2 * pad)
    }

    public func union(_ other: LGRect) -> LGRect {
        let minX = Swift.min(self.minX, other.minX)
        let minY = Swift.min(self.minY, other.minY)
        let maxX = Swift.max(self.maxX, other.maxX)
        let maxY = Swift.max(self.maxY, other.maxY)
        return LGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Round to whole device pixels, matching the reference implementation's
    /// `_getPixelRect` so the CPU renderer and the shader agree on edges.
    public func roundedToPixels(scale: Double) -> LGRect {
        LGRect(
            x: (x * scale).rounded(),
            y: (y * scale).rounded(),
            width: (width * scale).rounded(),
            height: (height * scale).rounded()
        )
    }
}
