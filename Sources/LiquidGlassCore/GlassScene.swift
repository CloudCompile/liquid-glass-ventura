import Foundation

/// A layer in the scene behind the glass.
///
/// Layers are painted in the order they appear in ``GlassScene/layers``; a
/// glass panel samples everything painted *before* it, which is what produces
/// glass-on-glass refraction when two panels overlap.
public struct SceneLayer: Sendable {
    public enum Kind: Sendable {
        /// A pre-rasterised image (the equivalent of an `html-to-image`
        /// snapshot or a live `drawImage` of an `img`/`video`/`canvas`).
        case image(RGBAImage)
        /// A flat fill, handy for backgrounds and debug backdrops.
        case fill(RGBAColor)
    }

    public var kind: Kind
    /// Where the layer lands in root coordinates.
    public var frame: LGRect
    /// True for content that changes every frame (`data-dynamic`, video).
    /// Dynamic layers force the panels overlapping them to re-shade.
    public var isDynamic: Bool
    /// Painting traits used to sort this layer against its siblings.
    public var traits: StackingTraits
    /// The glass config to use when this layer is itself a glass panel.
    /// `nil` means the layer is ordinary content.
    public var glassConfig: GlassConfig?

    public init(
        kind: Kind,
        frame: LGRect,
        isDynamic: Bool = false,
        traits: StackingTraits = StackingTraits(),
        glassConfig: GlassConfig? = nil
    ) {
        self.kind = kind
        self.frame = frame
        self.isDynamic = isDynamic
        self.traits = traits
        self.glassConfig = glassConfig
    }

    public static func fill(_ color: RGBAColor, frame: LGRect, traits: StackingTraits = StackingTraits()) -> SceneLayer {
        SceneLayer(kind: .fill(color), frame: frame, traits: traits)
    }

    public static func image(_ image: RGBAImage, frame: LGRect, traits: StackingTraits = StackingTraits()) -> SceneLayer {
        SceneLayer(kind: .image(image), frame: frame, traits: traits)
    }

    public var isGlass: Bool { glassConfig != nil }
}

/// A root scene plus the glass panels that float above it.
///
/// This is the headless equivalent of `LiquidGlass.init({ root, glassElements })`.
/// It owns the same three-phase pipeline as the web library:
///
///   1. Paint every layer that comes before a panel into a local crop.
///   2. Run the glass shader over that crop.
///   3. Composite the shaded panel back onto the scene, so a later panel sees
///      it and can refract it in turn.
public struct GlassScene: Sendable {
    /// The root's bounds in points.
    public var bounds: LGRect
    /// Device pixel ratio used for all rasterisation.
    public var scale: Double
    /// Scene layers, in authoring order. Painting order is derived from each
    /// layer's `traits`, matching the browser's two-pass stacking rule.
    public var layers: [SceneLayer]
    /// Indices into `layers` that are glass panels.
    public var glassIndices: [Int]
    /// Optional per-instance config overrides applied to every panel.
    public var defaults: GlassConfig

    public init(
        bounds: LGRect,
        scale: Double = 2,
        layers: [SceneLayer] = [],
        glassIndices: [Int] = [],
        defaults: GlassConfig = .standard
    ) {
        self.bounds = bounds
        self.scale = scale
        self.layers = layers
        self.glassIndices = glassIndices
        self.defaults = defaults
    }

    /// Render the whole scene.
    ///
    /// Layers are painted in stacking order. When a glass layer is reached it
    /// is shaded against everything painted so far — which includes any glass
    /// panel painted earlier — and then composited back. That single-pass
    /// accumulation is what gives overlapping panels their layered refraction,
    /// and it mirrors the reference implementation's per-panel scene assembly.
    public func render(background: RGBAColor = RGBAColor(r: 1, g: 1, b: 1, a: 1)) -> RGBAImage {
        let w = Int((bounds.width * scale).rounded())
        let h = Int((bounds.height * scale).rounded())
        var canvas = RGBAImage(width: w, height: h, fill: background)
        guard w > 0, h > 0 else { return canvas }

        for index in paintingOrder(layers.map(\.traits)) {
            let layer = layers[index]
            if glassIndices.contains(index), let config = layer.glassConfig {
                canvas = shadeGlass(layer: layer, config: config, into: canvas)
            } else {
                paint(layer: layer, into: &canvas)
            }
        }

        return canvas
    }

    private func shadeGlass(layer: SceneLayer, config: GlassConfig, into canvas: RGBAImage) -> RGBAImage {
        let pad = glassShadowPad * scale
        let pixelFrame = layer.frame.roundedToPixels(scale: scale)
        let paddedFrame = LGRect(
            x: pixelFrame.x - pad,
            y: pixelFrame.y - pad,
            width: pixelFrame.width + pad * 2,
            height: pixelFrame.height + pad * 2
        )

        let backdrop = canvas.cropped(to: paddedFrame, outOfBounds: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        let renderer = SoftwareGlassRenderer(backdrop: backdrop)
        let shaded = renderer.renderPanel(config: config, size: layer.frame.size, scale: scale)
        var out = canvas
        out.composite(shaded, at: paddedFrame.origin, referenceAlpha: config.referenceAlphaCompositing)
        return out
    }

    private func paint(layer: SceneLayer, into canvas: inout RGBAImage) {
        switch layer.kind {
        case .fill(let color):
            let rect = layer.frame.roundedToPixels(scale: scale)
            let x0 = max(Int(rect.x), 0)
            let y0 = max(Int(rect.y), 0)
            let x1 = min(Int(rect.maxX), canvas.width)
            let y1 = min(Int(rect.maxY), canvas.height)
            guard x0 < x1 && y0 < y1 else { return }
            for y in y0..<y1 {
                for x in x0..<x1 {
                    if color.a >= 1 {
                        canvas.setColor(x: x, y: y, color)
                    } else {
                        canvas.setColor(x: x, y: y, color.over(canvas.color(x: x, y: y)))
                    }
                }
            }
        case .image(let image):
            canvas.composite(image, at: LGPoint(x: layer.frame.x * scale, y: layer.frame.y * scale))
        }
    }
}
