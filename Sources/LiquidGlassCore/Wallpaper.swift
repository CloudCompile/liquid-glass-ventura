import Foundation

/// A deterministic pseudo-random generator (SplitMix64).
///
/// Seeded generation keeps every screenshot byte-reproducible, which is what
/// lets the docs pipeline diff renders in CI.
public struct SplitMix64 {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in `0 ... 1`.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// Uniform in `lower ... upper`.
    public mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + unit() * (upper - lower)
    }
}

/// Procedural backgrounds for demos, tests, and the screenshot gallery.
///
/// Liquid glass is only interesting when it has something worth refracting, so
/// the core ships a few deterministic backdrops that exercise different
/// frequencies: smooth mesh gradients, hard-edged grids, and text.
public enum Wallpaper {

    /// A smooth multi-blob gradient in the spirit of the macOS Ventura
    /// wallpaper: several coloured light sources blended additively, then
    /// tone-mapped.
    public static func mesh(
        size: LGSize,
        scale: Double = 2,
        seed: UInt64 = 0x5EED,
        palette: [RGBColor] = defaultPalette,
        blobs: Int = 7
    ) -> RGBAImage {
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        var image = RGBAImage(width: w, height: h)
        guard w > 0, h > 0 else { return image }

        var rng = SplitMix64(seed: seed)
        struct Blob {
            var x: Double
            var y: Double
            var radius: Double
            var color: RGBColor
            var strength: Double
        }
        var lights: [Blob] = []
        for i in 0..<max(blobs, 1) {
            let color = palette[i % palette.count]
            lights.append(Blob(
                x: rng.range(-0.15, 1.15),
                y: rng.range(-0.15, 1.15),
                radius: rng.range(0.35, 0.95),
                color: color,
                strength: rng.range(0.55, 1.0)
            ))
        }
        // A dark base so the lights read as emissive rather than washed out.
        let base = RGBColor(r: 0.035, g: 0.045, b: 0.075)

        for y in 0..<h {
            let v = Double(y) / Double(max(h - 1, 1))
            for x in 0..<w {
                let u = Double(x) / Double(max(w - 1, 1))
                var r = base.r, g = base.g, b = base.b
                for light in lights {
                    let dx = (u - light.x)
                    let dy = (v - light.y)
                    let d = (dx * dx + dy * dy).squareRoot() / light.radius
                    let falloff = max(0, 1 - d)
                    let weight = falloff * falloff * light.strength
                    r += light.color.r * weight
                    g += light.color.g * weight
                    b += light.color.b * weight
                }
                // Reinhard-ish tone map keeps highlights from clipping hard.
                r = r / (1 + r * 0.55)
                g = g / (1 + g * 0.55)
                b = b / (1 + b * 0.55)
                image.setColor(x: x, y: y, RGBAColor(r: r, g: g, b: b, a: 1))
            }
        }
        return image
    }

    /// A high-frequency backdrop: a grid with numbered cells. Ideal for showing
    /// refraction and chromatic aberration, because straight lines bend and
    /// fringes become obvious.
    public static func grid(
        size: LGSize,
        scale: Double = 2,
        cell: Double = 28,
        background: RGBAColor = RGBAColor(r: 0.06, g: 0.07, b: 0.10, a: 1),
        line: RGBAColor = RGBAColor(r: 0.30, g: 0.55, b: 0.95, a: 0.55),
        labelEvery: Int = 2
    ) -> RGBAImage {
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        var image = RGBAImage(width: w, height: h, fill: background)
        guard w > 0, h > 0 else { return image }
        let step = max(cell * scale, 4)
        var index = 0
        var x = 0.0
        while x < Double(w) {
            for y in 0..<h {
                image.setColor(x: Int(x), y: y, line)
            }
            x += step
        }
        var y = 0.0
        while y < Double(h) {
            for xp in 0..<w {
                image.setColor(x: xp, y: Int(y), line)
            }
            y += step
        }
        if labelEvery > 0 {
            var row = 0
            var cy = step * 0.25
            while cy < Double(h) {
                var col = 0
                var cx = step * 0.25
                while cx < Double(w) {
                    if row % labelEvery == 0 && col % labelEvery == 0 {
                        TextRasterizer.draw(
                            "\(index)",
                            into: &image,
                            at: LGPoint(x: cx, y: cy),
                            color: RGBAColor(r: 0.85, g: 0.90, b: 1.0, a: 0.75),
                            scale: max(Int(scale), 1)
                        )
                    }
                    index += 1
                    col += 1
                    cx += step
                }
                row += 1
                cy += step
            }
        }
        return image
    }

    /// Diagonal colour bands. Good for demonstrating chromatic dispersion
    /// because adjacent hues shift differently under refraction.
    public static func spectrum(size: LGSize, scale: Double = 2, bands: Int = 12) -> RGBAImage {
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        var image = RGBAImage(width: w, height: h)
        guard w > 0, h > 0 else { return image }
        for y in 0..<h {
            let v = Double(y) / Double(max(h - 1, 1))
            for x in 0..<w {
                let u = Double(x) / Double(max(w - 1, 1))
                let t = ((u + v) * 0.5 * Double(bands)).truncatingRemainder(dividingBy: 1)
                let hue = t * 6
                let c = hsvToRGB(hue: hue, saturation: 0.75, value: 0.95)
                image.setColor(x: x, y: y, RGBAColor(c, alpha: 1))
            }
        }
        return image
    }

    /// A dark scene with scattered bright specks — stresses specular highlights
    /// and edge lighting.
    public static func starfield(size: LGSize, scale: Double = 2, seed: UInt64 = 99, count: Int = 900) -> RGBAImage {
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        var image = RGBAImage(width: w, height: h, fill: RGBAColor(r: 0.02, g: 0.025, b: 0.045, a: 1))
        guard w > 0, h > 0 else { return image }
        var rng = SplitMix64(seed: seed)
        for _ in 0..<count {
            let cx = rng.range(0, Double(w))
            let cy = rng.range(0, Double(h))
            let radius = rng.range(0.6, 2.6) * scale
            let brightness = rng.range(0.35, 1.0)
            let tint = rng.range(0.85, 1.0)
            let r = Int((cx - radius).rounded(.down))
            let r2 = Int((cx + radius).rounded(.up))
            let c1 = Int((cy - radius).rounded(.down))
            let c2 = Int((cy + radius).rounded(.up))
            for y in c1...c2 {
                for x in r...r2 {
                    let dx = Double(x) - cx
                    let dy = Double(y) - cy
                    let d = (dx * dx + dy * dy).squareRoot()
                    guard d <= radius else { continue }
                    let glow = pow(1 - d / radius, 1.6) * brightness
                    let dst = image.color(x: x, y: y)
                    let src = RGBAColor(r: glow * tint, g: glow * 0.97, b: glow, a: 1)
                    image.setColor(x: x, y: y, RGBAColor(
                        r: min(dst.r + src.r, 1),
                        g: min(dst.g + src.g, 1),
                        b: min(dst.b + src.b, 1),
                        a: 1
                    ))
                }
            }
        }
        return image
    }

    public static let defaultPalette: [RGBColor] = [
        RGBColor(hex: 0x3B82F6),
        RGBColor(hex: 0x8B5CF6),
        RGBColor(hex: 0xEC4899),
        RGBColor(hex: 0xF97316),
        RGBColor(hex: 0x14B8A6),
        RGBColor(hex: 0x06B6D4),
    ]

    private static func hsvToRGB(hue: Double, saturation: Double, value: Double) -> RGBColor {
        let c = value * saturation
        let hh = hue / 60
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let m = value - c
        var r = 0.0, g = 0.0, b = 0.0
        switch hh {
        case ..<1: r = c; g = x
        case ..<2: r = x; g = c
        case ..<3: g = c; b = x
        case ..<4: g = x; b = c
        case ..<5: r = x; b = c
        default: r = c; b = x
        }
        return RGBColor(r: r + m, g: g + m, b: b + m)
    }
}
