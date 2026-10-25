#if os(macOS)
import SwiftUI
import AppKit
import LiquidGlassCore

/// Groups related glass surfaces so they merge into one another.
///
/// On macOS 26 and later this forwards to the system `GlassEffectContainer`. On
/// Ventura through macOS 15 the port does the merging itself: the surfaces that
/// come within `spacing` of each other are collected, and one continuous glass
/// panel is drawn behind their union instead of one panel per surface. That is
/// what makes the group read as a single piece of material rather than as
/// separate controls that happen to be near each other.
///
/// ```swift
/// GlassEffectContainer(spacing: 24) {
///     HStack(spacing: 24) {
///         Image(systemName: "scribble.variable").glassButton()
///         Image(systemName: "eraser.fill").glassButton()
///     }
/// }
/// ```
///
/// The union silhouette is built from the members' outlines, so where two
/// surfaces meet the join is a hard union. The system material bridges that gap
/// with a metaball curve instead.
public struct GlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    public init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    /// The coordinate space the children report their frames in.
    private static var space: NamedCoordinateSpace { .named("liquidGlassContainer") }

    public var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            NativeGlassEffectContainer(spacing: spacing, content: content)
        } else {
            ported
        }
        #else
        ported
        #endif
    }

    /// The ported container: one merged panel behind each cluster of nearby
    /// surfaces. Used on macOS 13–15 and on any toolchain older than Xcode 26.
    private var ported: some View {
        // The merged panels go in the background rather than around the
        // content, so they sit behind it and the container never changes the
        // layout it wraps.
        content
            .environment(\.liquidGlassContainerActive, true)
            .backgroundPreferenceValue(GlassSurfaceRegistryKey.self) { registrations in
                GeometryReader { geometry in
                    let origin = geometry.frame(in: Self.space).origin
                    ZStack(alignment: .topLeading) {
                        ForEach(
                            GlassCluster.cluster(registrations, spacing: spacing, origin: origin)
                        ) { cluster in
                            MergedGlassPanel(cluster: cluster)
                        }
                    }
                }
            }
            .coordinateSpace(name: "liquidGlassContainer")
    }
}

/// What a glass surface tells its enclosing container about itself.
struct GlassSurfaceRegistration: Equatable {
    /// The surface's frame in the container's coordinate space.
    let frame: CGRect
    let config: GlassConfig
    let backdrop: GlassBackdrop

    /// `GlassBackdrop` carries a `CGImage` or an `NSView`, neither of which is
    /// equatable, so compare the case and ignore the payload. Two surfaces whose
    /// backdrops differ only in payload would re-render once and then settle.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.frame == rhs.frame
            && lhs.config == rhs.config
            && lhs.backdrop.sameKind(as: rhs.backdrop)
    }
}

extension GlassBackdrop {
    func sameKind(as other: GlassBackdrop) -> Bool {
        switch (self, other) {
        case (.nativeBlur, .nativeBlur): return true
        case (.color, .color): return true
        case (.image, .image): return true
        case (.view, .view): return true
        default: return false
        }
    }
}

struct GlassSurfaceRegistryKey: PreferenceKey {
    static var defaultValue: [GlassSurfaceRegistration] { [] }
    static func reduce(value: inout [GlassSurfaceRegistration], nextValue: () -> [GlassSurfaceRegistration]) {
        value.append(contentsOf: nextValue())
    }
}

/// A group of surfaces close enough together to share one panel.
struct GlassCluster: Identifiable {
    let id: Int
    /// The union box of the members, in container-local coordinates.
    var bounds: CGRect
    /// The corner radius the merged panel takes.
    var cornerRadius: CGFloat
    var config: GlassConfig
    var backdrop: GlassBackdrop

    /// Group the registrations into clusters.
    ///
    /// Two surfaces join when their frames come within `spacing` of each other,
    /// transitively; see `GlassClusterer`. The merged panel is a single rounded
    /// rectangle spanning the cluster, which is the shape the CPU renderer
    /// produces for the same group — so what the render CLI shows in
    /// `docs/screenshots/merged-cluster.png` is what this draws on screen.
    static func cluster(
        _ registrations: [GlassSurfaceRegistration],
        spacing: CGFloat,
        origin: CGPoint
    ) -> [GlassCluster] {
        guard !registrations.isEmpty else { return [] }

        let local = registrations.map { registration in
            LGRect(
                x: registration.frame.minX - origin.x,
                y: registration.frame.minY - origin.y,
                width: registration.frame.width,
                height: registration.frame.height
            )
        }

        let groups = GlassClusterer.clusters(frames: local, spacing: Double(spacing))
        return groups.enumerated().map { order, members in
            let box = GlassClusterer.bounds(of: local, indices: members)
            // The merged panel keeps the members' corner radius, so a merged
            // group still reads as the same control shape, just spanning more.
            let radius = members
                .map { CGFloat(registrations[$0].config.cornerRadius) }
                .max() ?? 0
            return GlassCluster(
                id: order,
                bounds: CGRect(x: box.x, y: box.y, width: box.width, height: box.height),
                cornerRadius: min(radius, CGFloat(min(box.width, box.height) / 2)),
                config: registrations[members[0]].config,
                backdrop: registrations[members[0]].backdrop
            )
        }
    }
}

/// One merged panel: a single glass surface covering the cluster's union.
private struct MergedGlassPanel: View {
    let cluster: GlassCluster

    var body: some View {
        MergedGlassView(cluster: cluster)
            .frame(width: cluster.bounds.width, height: cluster.bounds.height)
            .position(x: cluster.bounds.midX, y: cluster.bounds.midY)
            .allowsHitTesting(false)
    }
}

private struct MergedGlassView: NSViewRepresentable {
    let cluster: GlassCluster

    func makeNSView(context: Context) -> MergedGlassNSView {
        let view = MergedGlassNSView()
        view.configure(cluster: cluster)
        return view
    }

    func updateNSView(_ view: MergedGlassNSView, context: Context) {
        view.configure(cluster: cluster)
    }
}

/// Draws one glass panel spanning a whole cluster.
///
/// The panel is rendered for the cluster's bounding box, so the bevel and the
/// refraction run around the group rather than restarting at each member. The
/// blur behind it is a single `NSVisualEffectView` masked to the same outline,
/// so the backdrop is continuous across the group.
final class MergedGlassNSView: NSView {
    private var config: GlassConfig = .standard
    private var backdrop: GlassBackdrop = .nativeBlur
    private var panelPath = CGPath(rect: .zero, transform: nil)
    private var image: CGImage?
    private var pending = false
    private let blurView = NSVisualEffectView()
    private let maskLayer = CAShapeLayer()

    private static let queue = DispatchQueue(label: "com.liquidglass.merged", qos: .userInitiated)

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        blurView.material = .hudWindow
        blurView.blendingMode = .withinWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.mask = maskLayer
        addSubview(blurView)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func configure(cluster: GlassCluster) {
        config = cluster.config
        backdrop = cluster.backdrop
        // The view is sized to the cluster, so the panel is the view's own box.
        let inset = CGRect(x: 0, y: 0, width: cluster.bounds.width, height: cluster.bounds.height)
        panelPath = CGPath(
            roundedRect: inset,
            cornerWidth: cluster.cornerRadius,
            cornerHeight: cluster.cornerRadius,
            transform: nil
        )
        maskLayer.path = panelPath
        image = nil
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        blurView.frame = bounds
        maskLayer.frame = bounds
        maskLayer.path = panelPath
        // AppKit views are bottom-up, the same as a `CGPath` built from a
        // rect, so the mask needs no extra flip.
        blurView.layer?.mask = maskLayer
        if blurView.isHidden != !isNativeBackdrop {
            blurView.isHidden = !isNativeBackdrop
        }
    }

    private var isNativeBackdrop: Bool {
        if case .nativeBlur = backdrop { return true }
        return false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width >= 1, bounds.height >= 1,
              let context = NSGraphicsContext.current?.cgContext else { return }

        // The drop shadow follows the union, drawn outside the clip.
        if config.shadowOpacity > 0 {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 0, height: -config.shadowOffsetY),
                blur: config.shadowSpread,
                color: NSColor.black.withAlphaComponent(config.shadowOpacity).cgColor
            )
            context.addPath(panelPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            context.restoreGState()
        }

        if image == nil && !pending {
            pending = true
            startRender()
        }

        guard let image else { return }
        let pad = CGFloat(glassShadowPad)
        let target = CGRect(
            x: -pad, y: -pad,
            width: bounds.width + pad * 2, height: bounds.height + pad * 2
        )
        context.saveGState()
        // Clip to the union so the panel takes the merged silhouette.
        context.addPath(panelPath)
        context.clip()
        context.translateBy(x: 0, y: target.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        if isNativeBackdrop {
            context.setBlendMode(.plusLighter)
        }
        context.draw(image, in: target)
        context.restoreGState()
    }

    private func startRender() {
        guard let window else { pending = false; return }
        let scale = window.backingScaleFactor
        let pad = CGFloat(glassShadowPad)
        let pixelWidth = Int((bounds.width + pad * 2) * scale)
        let pixelHeight = Int((bounds.height + pad * 2) * scale)

        var renderConfig = config
        var backdropImage: RGBAImage
        switch backdrop {
        case .nativeBlur:
            // Additive lighting over the masked system blur.
            renderConfig.shadowOpacity = 0
            backdropImage = RGBAImage(width: 1, height: 1, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        case .color(let color):
            backdropImage = RGBAImage(width: 1, height: 1, fill: RGBAColor(color, alpha: 1))
        case .image(let cgImage):
            guard let image = RGBAImage(cgImage: cgImage, width: pixelWidth, height: pixelHeight) else {
                pending = false
                return
            }
            backdropImage = image
        case .view(let view):
            let rect = convert(bounds.insetBy(dx: -pad, dy: -pad), to: view)
            guard let image = GlassBitmap.capture(behind: view, rect: rect, excluding: nil, scale: scale) else {
                pending = false
                return
            }
            backdropImage = image
        }

        let size = LGSize(width: bounds.width, height: bounds.height)
        Self.queue.async { [weak self] in
            guard let self else { return }
            let shaded = SoftwareGlassRenderer(backdrop: backdropImage)
                .renderPanel(config: renderConfig, size: size, scale: Double(scale))
            let cg = GlassBitmap.cgImage(from: shaded)
            DispatchQueue.main.async {
                self.image = cg
                self.pending = false
                self.needsDisplay = true
            }
        }
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private struct NativeGlassEffectContainer<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    var body: some View {
        // Qualified, because this module declares a `GlassEffectContainer` of
        // its own and an unqualified reference would recurse.
        SwiftUI.GlassEffectContainer(spacing: spacing) { content }
    }
}
#endif
#endif
