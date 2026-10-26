#if os(macOS)
import AppKit
import LiquidGlassCore

/// A ready-made AppKit view that draws a glass surface behind its subviews.
///
/// Use this when the host is AppKit rather than SwiftUI. On macOS 26 and later
/// prefer the system `NSGlassEffectView`; this class is the back-deployment
/// path for Ventura through macOS 15.
///
/// ```swift
/// let glass = GlassView(frame: rect, config: .panel)
/// glass.cornerRadius = 24
/// container.addSubview(glass)      // behind the content it should refract
/// ```
///
/// The view refracts what is drawn *behind* it, which it reads by asking the
/// superview to redraw the region it covers with itself temporarily hidden.
/// That is the correct arrangement for AppKit: add the glass first, then the
/// content on top.
open class GlassView: NSView {

    /// The optics for this surface. Assigning re-renders.
    public var config: GlassConfig = .standard {
        didSet { invalidateGlass() }
    }

    /// Corner radius in points. Defaults to `config.cornerRadius`.
    public var cornerRadius: CGFloat {
        get { CGFloat(config.cornerRadius) }
        set {
            config.cornerRadius = Double(newValue)
            invalidateGlass()
        }
    }

    /// The outline of the surface.
    public var shape: GlassShape = .rect(cornerRadius: 18) {
        didSet { invalidateGlass() }
    }

    /// Refract the desktop wallpaper rather than the view hierarchy.
    ///
    /// Useful for a full-screen glass overlay, where capturing the hierarchy
    /// would be expensive.
    public var wallpaperBackdrop: Bool = false

    private var rendered: CGImage?
    private var renderedSize: CGSize = .zero
    private var renderedConfig: GlassConfig?
    private var pending = false

    private static let queue = DispatchQueue(label: "com.liquidglass.glassview", qos: .userInitiated)

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    public convenience init(frame frameRect: NSRect, config: GlassConfig) {
        self.init(frame: frameRect)
        self.config = config
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = false
    }

    open override var isOpaque: Bool { false }

    /// Glass is decoration; events belong to the content in front of it.
    open override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func invalidateGlass() {
        rendered = nil
        needsDisplay = true
    }

    open override func layout() {
        super.layout()
        if bounds.size != renderedSize { invalidateGlass() }
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateGlass()
    }

    open override func draw(_ dirtyRect: NSRect) {
        guard bounds.width >= 1, bounds.height >= 1,
              let context = NSGraphicsContext.current?.cgContext else { return }

        if rendered == nil && !pending {
            pending = true
            startRender()
        }

        guard let rendered else { return }
        let pad = CGFloat(glassShadowPad)
        let target = CGRect(
            x: -pad, y: -pad,
            width: bounds.width + pad * 2, height: bounds.height + pad * 2
        )
        context.saveGState()
        // `CGImage` rows run top-down; the AppKit context is bottom-up.
        context.translateBy(x: 0, y: target.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(rendered, in: target)
        context.restoreGState()
    }

    private func startRender() {
        let scale = window?.backingScaleFactor ?? 2
        let pad = CGFloat(glassShadowPad)
        var config = self.config
        config.cornerRadius = shape.cornerRadius(for: LGSize(width: bounds.width, height: bounds.height))
        config.zRadius = min(config.zRadius, max(Double(bounds.height), 1))

        let pixelWidth = Int((bounds.width + pad * 2) * scale)
        let pixelHeight = Int((bounds.height + pad * 2) * scale)

        let backdrop: RGBAImage?
        if wallpaperBackdrop, let screen = window?.screen, let wallpaper = GlassView.wallpaperImage(for: screen) {
            backdrop = RGBAImage(cgImage: wallpaper, width: pixelWidth, height: pixelHeight)
        } else if let superview {
            let rect = convert(bounds.insetBy(dx: -pad, dy: -pad), to: superview)
            backdrop = GlassBitmap.capture(behind: superview, rect: rect, excluding: self, scale: scale)
        } else {
            backdrop = RGBAImage(width: 1, height: 1, fill: RGBAColor(r: 0.5, g: 0.5, b: 0.55, a: 1))
        }

        guard let backdrop else {
            pending = false
            return
        }

        let size = LGSize(width: bounds.width, height: bounds.height)
        renderedSize = bounds.size
        renderedConfig = config
        Self.queue.async { [weak self] in
            guard let self else { return }
            let shaded = SoftwareGlassRenderer(backdrop: backdrop)
                .renderPanel(config: config, size: size, scale: Double(scale))
            let image = GlassBitmap.cgImage(from: shaded)
            DispatchQueue.main.async {
                // Drop the result if the geometry changed while rendering.
                guard self.renderedConfig == config, self.renderedSize == self.bounds.size else {
                    self.pending = false
                    self.needsDisplay = true
                    return
                }
                self.rendered = image
                self.pending = false
                self.needsDisplay = true
            }
        }
    }

    /// The current desktop wallpaper, if it can be read.
    private static func wallpaperImage(for screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url) else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#endif
