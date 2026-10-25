import Foundation

/// A simple 8-bit RGBA raster with straight (non-premultiplied) alpha.
///
/// This is the core's image type. It is deliberately dependency-free so the
/// reference renderer runs anywhere Swift runs, and so tests can assert on
/// exact pixel values.
public struct RGBAImage: Equatable, Sendable {
    public private(set) var width: Int
    public private(set) var height: Int
    /// Row-major RGBA bytes, `width * height * 4` long.
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int, fill: RGBAColor = .clear) {
        self.width = max(0, width)
        self.height = max(0, height)
        let c = Self.pack(fill)
        self.pixels = [UInt8](repeating: 0, count: self.width * self.height * 4)
        var i = 0
        while i < pixels.count {
            pixels[i] = c.0
            pixels[i + 1] = c.1
            pixels[i + 2] = c.2
            pixels[i + 3] = c.3
            i += 4
        }
    }

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 4, "pixel buffer size mismatch")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public var isEmpty: Bool { width == 0 || height == 0 }

    private static func pack(_ c: RGBAColor) -> (UInt8, UInt8, UInt8, UInt8) {
        (
            UInt8(min(max(c.r, 0), 1) * 255 + 0.5),
            UInt8(min(max(c.g, 0), 1) * 255 + 0.5),
            UInt8(min(max(c.b, 0), 1) * 255 + 0.5),
            UInt8(min(max(c.a, 0), 1) * 255 + 0.5)
        )
    }

    @inline(__always)
    public func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    @inline(__always)
    public func color(x: Int, y: Int) -> RGBAColor {
        guard contains(x: x, y: y) else { return .clear }
        let i = (y * width + x) * 4
        return RGBAColor(
            r: Double(pixels[i]) / 255,
            g: Double(pixels[i + 1]) / 255,
            b: Double(pixels[i + 2]) / 255,
            a: Double(pixels[i + 3]) / 255
        )
    }

    @inline(__always)
    public mutating func setColor(x: Int, y: Int, _ c: RGBAColor) {
        guard contains(x: x, y: y) else { return }
        let i = (y * width + x) * 4
        let p = Self.pack(c)
        pixels[i] = p.0
        pixels[i + 1] = p.1
        pixels[i + 2] = p.2
        pixels[i + 3] = p.3
    }

    /// Bilinear sample in pixel coordinates with clamp-to-edge addressing,
    /// matching the shader's `LINEAR` + `CLAMP_TO_EDGE` texture setup.
    public func sampleBilinear(x: Double, y: Double) -> RGBAColor {
        guard !isEmpty else { return .clear }
        let fx = x - 0.5
        let fy = y - 0.5
        let x0 = Int(fx.rounded(.down))
        let y0 = Int(fy.rounded(.down))
        let tx = fx - Double(x0)
        let ty = fy - Double(y0)

        @inline(__always) func fetch(_ ix: Int, _ iy: Int) -> RGBAColor {
            let cx = min(max(ix, 0), width - 1)
            let cy = min(max(iy, 0), height - 1)
            return color(x: cx, y: cy)
        }

        let c00 = fetch(x0, y0)
        let c10 = fetch(x0 + 1, y0)
        let c01 = fetch(x0, y0 + 1)
        let c11 = fetch(x0 + 1, y0 + 1)
        let top = RGBAColor(
            r: c00.r + (c10.r - c00.r) * tx,
            g: c00.g + (c10.g - c00.g) * tx,
            b: c00.b + (c10.b - c00.b) * tx,
            a: c00.a + (c10.a - c00.a) * tx
        )
        let bottom = RGBAColor(
            r: c01.r + (c11.r - c01.r) * tx,
            g: c01.g + (c11.g - c01.g) * tx,
            b: c01.b + (c11.b - c01.b) * tx,
            a: c01.a + (c11.a - c01.a) * tx
        )
        return RGBAColor(
            r: top.r + (bottom.r - top.r) * ty,
            g: top.g + (bottom.g - top.g) * ty,
            b: top.b + (bottom.b - top.b) * ty,
            a: top.a + (bottom.a - top.a) * ty
        )
    }

    /// Crop a sub-rectangle.
    ///
    /// Regions outside the receiver are filled with `outOfBounds`. The scene
    /// compositor passes white here, matching the reference implementation's
    /// white scene canvas, so a panel near the edge samples a plausible
    /// backdrop instead of transparent black.
    public func cropped(to rect: LGRect, outOfBounds: RGBAColor = .clear) -> RGBAImage {
        let w = Int(rect.width.rounded())
        let h = Int(rect.height.rounded())
        var out = RGBAImage(width: w, height: h, fill: outOfBounds)
        guard w > 0, h > 0 else { return out }
        let ox = Int(rect.x.rounded())
        let oy = Int(rect.y.rounded())
        for y in 0..<h {
            let sy = oy + y
            guard sy >= 0 && sy < height else { continue }
            for x in 0..<w {
                let sx = ox + x
                guard sx >= 0 && sx < width else { continue }
                out.setColor(x: x, y: y, color(x: sx, y: sy))
            }
        }
        return out
    }

    /// Source-over composite `other` on top of the receiver at `origin`.
    ///
    /// When `referenceAlpha` is set, the blend reproduces the reference
    /// library's canvas compositing (`rgb * alpha`, coverage `alpha²`) instead
    /// of textbook straight-alpha source-over; see `RGBAColor.referenceOver`.
    public mutating func composite(_ other: RGBAImage, at origin: LGPoint, referenceAlpha: Bool = false) {
        guard !other.isEmpty else { return }
        let ox = Int(origin.x.rounded())
        let oy = Int(origin.y.rounded())
        for y in 0..<other.height {
            let ty = oy + y
            guard ty >= 0 && ty < height else { continue }
            for x in 0..<other.width {
                let tx = ox + x
                guard tx >= 0 && tx < width else { continue }
                let src = other.color(x: x, y: y)
                if src.a <= 0 { continue }
                if src.a >= 1 {
                    setColor(x: tx, y: ty, src)
                } else {
                    let backdrop = color(x: tx, y: ty)
                    setColor(x: tx, y: ty, referenceAlpha ? src.referenceOver(backdrop) : src.over(backdrop))
                }
            }
        }
    }
}
