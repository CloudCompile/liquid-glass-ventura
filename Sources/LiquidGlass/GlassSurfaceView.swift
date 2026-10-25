#if os(macOS)
import SwiftUI
import AppKit
import LiquidGlassCore

/// The view that paints a glass surface on macOS 13 through 15.
///
/// It is composed of up to three stacked pieces, matching how the reference
/// library builds a panel:
///
///   1. a backdrop — the blurred or refracted content behind the glass,
///   2. the ported optics — refraction, bevel rim, edge highlight, specular,
///      tint, chromatic dispersion,
///   3. the drop shadow.
///
/// With `.nativeBlur` the first piece comes from `NSVisualEffectView` and only
/// the backdrop-independent lighting is drawn over it. With an image, colour,
/// or view backdrop, the optics are drawn in full and refract that backdrop.
struct GlassSurfaceView: View {
    let material: LiquidGlassMaterial
    let shape: GlassShape
    let prominence: Double
    let backdrop: GlassBackdrop
    let configOverride: GlassConfig?

    var body: some View {
        GeometryReader { geometry in
            let size = LGSize(width: geometry.size.width, height: geometry.size.height)
            let config = resolvedConfig(size: size)
            ZStack {
                switch backdrop {
                case .nativeBlur:
                    NativeBlurView(
                        material: config.blurAmount > 0.4 ? .hudWindow : .popover,
                        tintColor: config.tintColor,
                        tintStrength: config.tintStrength
                    )
                    GlassOpticsView(config: config, shape: shape, source: .highlights)
                    GlassShadowView(config: config, shape: shape)
                case .color(let color):
                    Color(red: color.r, green: color.g, blue: color.b)
                    GlassOpticsView(config: config, shape: shape, source: .color(color))
                case .image(let image):
                    GlassOpticsView(config: config, shape: shape, source: .image(image))
                case .view(let view):
                    GlassOpticsView(config: config, shape: shape, source: .view(view))
                }
            }
            .clipShape(shape.swiftUIShape)
        }
        .allowsHitTesting(false)
    }

    private func resolvedConfig(size: LGSize) -> GlassConfig {
        var config = configOverride ?? material.config(prominence: prominence)
        config.cornerRadius = shape.cornerRadius(for: size)
        // A bevel cannot be deeper than the surface is tall.
        config.zRadius = min(config.zRadius, max(size.height, 1))
        return config
    }
}

/// The system backdrop blur, tinted by the port's tint term.
private struct NativeBlurView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let tintColor: RGBColor?
    let tintStrength: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        // `.withinWindow`, not `.behindWindow`: the glass sits over content in
        // the same window, so that is what it should blur.
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        if let tint = tintColor {
            view.layer?.backgroundColor = NSColor(
                srgbRed: CGFloat(tint.r), green: CGFloat(tint.g), blue: CGFloat(tint.b),
                alpha: CGFloat(min(tintStrength, 1))
            ).cgColor
        } else {
            view.layer?.backgroundColor = nil
        }
    }
}

/// Draws the ported optics for a panel, given where its backdrop comes from.
private struct GlassOpticsView: NSViewRepresentable {
    enum Source {
        /// Only the backdrop-independent lighting, drawn additively over the
        /// native blur.
        case highlights
        /// Refract a flat colour.
        case color(RGBColor)
        /// Refract a fixed image, the exact reference behaviour.
        case image(CGImage)
        /// Refract a live AppKit view.
        case view(NSView)
    }

    let config: GlassConfig
    let shape: GlassShape
    let source: Source

    func makeNSView(context: Context) -> OpticsNSView {
        let view = OpticsNSView()
        view.configure(config: config, shape: shape, source: source)
        return view
    }

    func updateNSView(_ view: OpticsNSView, context: Context) {
        view.configure(config: config, shape: shape, source: source)
    }
}

/// Draws the panel's drop shadow, which the reference renders outside the
/// panel's own bounds.
private struct GlassShadowView: NSViewRepresentable {
    let config: GlassConfig
    let shape: GlassShape

    func makeNSView(context: Context) -> ShadowNSView {
        let view = ShadowNSView()
        view.configure(config: config, shape: shape)
        return view
    }

    func updateNSView(_ view: ShadowNSView, context: Context) {
        view.configure(config: config, shape: shape)
    }
}

/// Renders one pass of the optical model into a `CGImage` and draws it.
///
/// The render happens on a background queue because a large panel is a few
/// hundred milliseconds of CPU work.
final class OpticsNSView: NSView {
    private var config: GlassConfig = .standard
    private var shape: GlassShape = .capsule
    private var source: GlassOpticsView.Source = .highlights
    private var image: CGImage?
    private var pending = false

    private static let queue = DispatchQueue(label: "com.liquidglass.optics", qos: .userInitiated)

    override var isOpaque: Bool { false }

    func configure(config: GlassConfig, shape: GlassShape, source: GlassOpticsView.Source) {
        self.config = config
        self.shape = shape
        self.source = source
        image = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width >= 1, bounds.height >= 1 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let pad = CGFloat(glassShadowPad)

        if image == nil && !pending {
            pending = true
            render(scale: scale, pad: pad)
        }

        guard let image, let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high
        let target = CGRect(
            x: -pad, y: -pad,
            width: bounds.width + pad * 2, height: bounds.height + pad * 2
        )
        context.saveGState()
        // `CGImage` rows run top-down; the AppKit context is bottom-up.
        context.translateBy(x: 0, y: target.height)
        context.scaleBy(x: 1, y: -1)
        if case .highlights = source {
            // Additive, so the rim and specular brighten the blur underneath
            // while the transparent interior leaves it untouched.
            context.setBlendMode(.plusLighter)
        }
        context.draw(image, in: target)
        context.restoreGState()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        image = nil
        needsDisplay = true
    }

    /// Build the backdrop image for this pass.
    ///
    /// Capturing a live view must happen on the main thread; everything after
    /// this point runs off it.
    private func backdropImage(scale: CGFloat, pad: CGFloat) -> RGBAImage? {
        let pixelWidth = Int((bounds.width + pad * 2) * scale)
        let pixelHeight = Int((bounds.height + pad * 2) * scale)
        switch source {
        case .highlights:
            // A black backdrop makes refraction a no-op, so only the lighting
            // terms survive — which is exactly what should be added to the blur.
            config.shadowOpacity = 0
            return RGBAImage(width: 1, height: 1, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        case .color(let color):
            return RGBAImage(width: 1, height: 1, fill: RGBAColor(color, alpha: 1))
        case .image(let cgImage):
            return RGBAImage(cgImage: cgImage, width: pixelWidth, height: pixelHeight)
        case .view(let view):
            let rect = convert(bounds.insetBy(dx: -pad, dy: -pad), to: view)
            return GlassBitmap.capture(behind: view, rect: rect, excluding: nil, scale: scale)
        }
    }

    private func render(scale: CGFloat, pad: CGFloat) {
        guard let backdrop = backdropImage(scale: scale, pad: pad) else {
            pending = false
            return
        }
        let config = self.config
        let size = LGSize(width: bounds.width, height: bounds.height)
        Self.queue.async { [weak self] in
            guard let self else { return }
            let shaded = SoftwareGlassRenderer(backdrop: backdrop)
                .renderPanel(config: config, size: size, scale: Double(scale))
            let cg = GlassBitmap.cgImage(from: shaded)
            DispatchQueue.main.async {
                self.image = cg
                self.pending = false
                self.needsDisplay = true
            }
        }
    }
}

/// Draws the panel's drop shadow with `CGContext.setShadow`, which is far
/// cheaper than rendering the shader's shadow profile and is visually
/// equivalent at the sizes a control uses.
final class ShadowNSView: NSView {
    private var config: GlassConfig = .standard
    private var shape: GlassShape = .capsule

    override var isOpaque: Bool { false }

    func configure(config: GlassConfig, shape: GlassShape) {
        self.config = config
        self.shape = shape
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard config.shadowOpacity > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 1, dy: 1)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -config.shadowOffsetY),
            blur: config.shadowSpread,
            color: NSColor.black.withAlphaComponent(config.shadowOpacity).cgColor
        )
        context.addPath(shape.path(in: rect))
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
        context.restoreGState()
    }
}
#endif
