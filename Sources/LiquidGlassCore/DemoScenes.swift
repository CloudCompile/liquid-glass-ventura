import Foundation

/// A named, reproducible render.
///
/// Every scene is built from the same primitives an app uses, so the images in
/// `docs/screenshots` double as an executable specification of the optics.
public struct DemoScene: Sendable {
    public let name: String
    public let summary: String
    private let builder: @Sendable (Double) -> GlassScene

    public init(name: String, summary: String, builder: @escaping @Sendable (Double) -> GlassScene) {
        self.name = name
        self.summary = summary
        self.builder = builder
    }

    public func render(scale: Double) -> RGBAImage {
        builder(scale).render()
    }
}

/// The scenes rendered by `liquidglass-render --all`.
public enum DemoScenes {

    public static let all: [DemoScene] = [
        hero,
        componentSheet,
        mergedCluster,
        magnifier,
        buttonStates,
        overlap,
        panelRow,
        spectrumRefraction,
        starfieldSpecular,
        magnifierOnly,
        bezelComparison,
        largeSurface,
        nativeBlurLighting,
    ]

    /// The component set the SwiftUI layer exposes, laid out the way the demo
    /// app arranges it: a glass title, the three button styles, circular icon
    /// buttons, and a pair of chips. Every surface here is one of the modifiers
    /// in `LiquidGlass`, so the image doubles as a preview of the API.
    public static let componentSheet = DemoScene(
        name: "components",
        summary: "The SwiftUI component set over a Ventura mesh gradient"
    ) { scale in
        let size = LGSize(width: 1000, height: 640)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.mesh(size: size, scale: scale, seed: 0x5EED, blobs: 8), frame: LGRect(origin: .zero, size: size)))
        // A transparent grid over the gradient: the lines give the refraction
        // fine detail to bend without hiding the colour behind it.
        scene.layers.append(.image(
            Wallpaper.grid(
                size: size,
                scale: scale,
                cell: 30,
                background: RGBAColor(r: 0, g: 0, b: 0, a: 0),
                line: RGBAColor(r: 1, g: 1, b: 1, a: 0.16),
                labelEvery: 0
            ),
            frame: LGRect(origin: .zero, size: size)
        ))

        var index = 0
        func addGlass(_ frame: LGRect, _ config: GlassConfig) {
            index += 1
            scene.layers.append(SceneLayer(
                kind: .image(RGBAImage(width: 0, height: 0)),
                frame: frame,
                traits: StackingTraits(positionIsStatic: false, zIndex: index, domIndex: index),
                glassConfig: config
            ))
            scene.glassIndices.append(scene.layers.count - 1)
        }

        // `.liquidGlass(.clear)` title.
        addGlass(
            LGRect(x: 250, y: 70, width: 500, height: 110),
            GlassConfig.materialClear
        )

        // The three button styles: regular, prominent, clear.
        let buttonConfigs: [GlassConfig] = [
            .materialButton(),
            .materialButton(prominent: true),
            .materialButton(clear: true),
        ]
        for (offset, config) in buttonConfigs.enumerated() {
            addGlass(
                LGRect(x: 214 + Double(offset) * 200, y: 250, width: 168, height: 52),
                config
            )
        }

        // Circular icon buttons.
        for offset in 0..<3 {
            addGlass(
                LGRect(x: 300 + Double(offset) * 78, y: 350, width: 58, height: 58),
                .materialButton(circle: true)
            )
        }

        // Chips, inside a `GlassEffectContainer` — so, exactly as on screen,
        // they are not two panels but one merged panel spanning the pair.
        let chipFrames = (0..<2).map { offset in
            LGRect(x: 372 + Double(offset) * 140, y: 460, width: 128, height: 72)
        }
        var chipConfig = GlassConfig.materialRegular
        chipConfig.cornerRadius = 18
        for indices in GlassClusterer.clusters(frames: chipFrames, spacing: 26) {
            addGlass(GlassClusterer.bounds(of: chipFrames, indices: indices), chipConfig)
        }

        // Labels under the surfaces, so the refraction has detail to bend.
        scene.layers.append(.image(componentLabels(size: size, scale: scale), frame: LGRect(origin: .zero, size: size)))
        return scene
    }

    /// What `GlassEffectContainer` does to a row of nearby surfaces.
    ///
    /// The top row is four separate panels. The bottom row is the same four
    /// controls drawn as one merged panel per cluster, which is the silhouette
    /// the container produces on Ventura: a single continuous piece of material
    /// spanning the group, with the bevel running around the outside instead of
    /// restarting at each control.
    public static let mergedCluster = DemoScene(
        name: "merged-cluster",
        summary: "Separate panels vs a container-merged cluster"
    ) { scale in
        let size = LGSize(width: 980, height: 460)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.mesh(size: size, scale: scale, seed: 0x9E11, blobs: 7), frame: LGRect(origin: .zero, size: size)))
        scene.layers.append(.image(
            Wallpaper.grid(
                size: size,
                scale: scale,
                cell: 26,
                background: RGBAColor(r: 0, g: 0, b: 0, a: 0),
                line: RGBAColor(r: 1, g: 1, b: 1, a: 0.14),
                labelEvery: 0
            ),
            frame: LGRect(origin: .zero, size: size)
        ))

        let memberWidth = 150.0
        let memberHeight = 84.0
        let spacing = 34.0
        let totalWidth = memberWidth * 4 + spacing * 3
        let startX = (size.width - totalWidth) / 2
        let memberConfig = GlassConfig.materialButton()

        // Top row: four independent surfaces, each with its own bevel.
        for index in 0..<4 {
            let frame = LGRect(
                x: startX + Double(index) * (memberWidth + spacing),
                y: 110,
                width: memberWidth,
                height: memberHeight
            )
            scene.layers.append(SceneLayer(
                kind: .image(RGBAImage(width: 0, height: 0)),
                frame: frame,
                traits: StackingTraits(positionIsStatic: false, zIndex: index + 1, domIndex: index + 1),
                glassConfig: memberConfig
            ))
            scene.glassIndices.append(scene.layers.count - 1)
        }

        // Bottom row: one merged panel spanning the whole cluster, clipped to
        // the union of the members' outlines.
        let frames = (0..<4).map { index in
            LGRect(
                x: startX + Double(index) * (memberWidth + spacing),
                y: 280,
                width: memberWidth,
                height: memberHeight
            )
        }
        var merged = memberConfig
        // The merged panel's bevel follows the group, not a member, so its
        // bevel depth is the group's.
        merged.cornerRadius = 18
        merged.zRadius = 26
        let union = GlassClusterer.clusters(frames: frames, spacing: spacing)
            .map { GlassClusterer.bounds(of: frames, indices: $0) }
        for (index, box) in union.enumerated() {
            scene.layers.append(SceneLayer(
                kind: .image(RGBAImage(width: 0, height: 0)),
                frame: box,
                traits: StackingTraits(positionIsStatic: false, zIndex: 10 + index, domIndex: 10 + index),
                glassConfig: merged
            ))
            scene.glassIndices.append(scene.layers.count - 1)
        }

        scene.layers.append(.image(mergedLabels(size: size, scale: scale), frame: LGRect(origin: .zero, size: size)))
        return scene
    }

    /// Labels for the merged-cluster scene.
    private static func mergedLabels(size: LGSize, scale: Double) -> RGBAImage {
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        var image = RGBAImage(width: w, height: h)
        let textScale = max(Int(scale * 2), 2)
        func centered(_ text: String, y: Double, alpha: Double) {
            let measured = TextRasterizer.measure(text, scale: textScale)
            TextRasterizer.draw(
                text,
                into: &image,
                at: LGPoint(x: (Double(w) - measured.width) / 2, y: y * scale),
                color: RGBAColor(r: 1, g: 1, b: 1, a: alpha),
                scale: textScale
            )
        }
        // In the margins, so the labels never cover the glass they describe.
        centered("FOUR SEPARATE PANELS", y: 66, alpha: 0.95)
        centered("ONE MERGED PANEL", y: 240, alpha: 0.95)
        centered("the gaps refract nothing", y: 404, alpha: 0.75)
        return image
    }

    /// Text for the component sheet, positioned to sit behind each surface.
    private static func componentLabels(size: LGSize, scale: Double) -> RGBAImage {
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        var image = RGBAImage(width: w, height: h)
        let textScale = max(Int(scale * 2), 2)

        func centered(_ text: String, y: Double, alpha: Double) {
            let measured = TextRasterizer.measure(text, scale: textScale)
            TextRasterizer.draw(
                text,
                into: &image,
                at: LGPoint(x: (Double(w) - measured.width) / 2, y: y * scale),
                color: RGBAColor(r: 1, g: 1, b: 1, a: alpha),
                scale: textScale
            )
        }

        centered("LIQUID GLASS", y: 108, alpha: 0.95)
        centered("CANCEL    CONFIRM    CLEAR", y: 268, alpha: 0.9)
        centered("SUB    BLUR", y: 486, alpha: 0.9)
        return image
    }

    // MARK: - Scenes

    /// The headline image: a glass pill and a glass card floating over a
    /// Ventura-style mesh gradient, with legible labels underneath so the
    /// refraction is visible.
    public static let hero = DemoScene(
        name: "hero",
        summary: "Glass pill + card over a mesh gradient"
    ) { scale in
        let size = LGSize(width: 960, height: 600)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.mesh(size: size, scale: scale, seed: 0x5EED), frame: LGRect(origin: .zero, size: size)))

        // Labels behind the glass: the refraction bends these.
        let grid = labelLayer(size: size, scale: scale, title: "LIQUID GLASS", subtitle: "MACOS VENTURA AND LATER")
        scene.layers.append(.image(grid, frame: LGRect(origin: .zero, size: size)))

        let pill = LGRect(x: 96, y: 132, width: 420, height: 128)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: pill,
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(
                blurAmount: 0.22,
                refraction: 0.62,
                cornerRadius: 64,
                zRadius: 44,
                tintStrength: 0.10,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)

        let card = LGRect(x: 548, y: 300, width: 336, height: 216)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: card,
            traits: StackingTraits(positionIsStatic: false, zIndex: 2, domIndex: 2),
            glassConfig: GlassConfig.panel
        ))
        scene.glassIndices.append(scene.layers.count - 1)
        return scene
    }

    /// A half-sphere dome magnifier, the `.dome` bevel mode.
    public static let magnifier = DemoScene(
        name: "magnifier",
        summary: "Dome bevel magnifier over a text grid"
    ) { scale in
        let size = LGSize(width: 900, height: 560)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.grid(size: size, scale: scale, cell: 26), frame: LGRect(origin: .zero, size: size)))
        let lens = LGRect(x: 300, y: 160, width: 300, height: 240)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: lens,
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(
                blurAmount: 0,
                refraction: 1.15,
                edgeHighlight: 0.10,
                cornerRadius: 118,
                zRadius: 118,
                shadowOpacity: 0.34,
                shadowSpread: 18,
                bevelMode: .dome,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)
        return scene
    }

    /// Side by side: idle, hovered, and pressed button states. The press state
    /// flattens the bevel and deepens the shadow, exactly as the reference
    /// library does.
    public static let buttonStates = DemoScene(
        name: "button-states",
        summary: "Idle, hover, and press variants of a glass button"
    ) { scale in
        let size = LGSize(width: 880, height: 320)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.mesh(size: size, scale: scale, seed: 0xB0B, blobs: 5), frame: LGRect(origin: .zero, size: size)))

        let base = GlassConfig(
                blurAmount: 0.16,
                refraction: 0.5,
                edgeHighlight: 0.09,
                cornerRadius: 26,
                zRadius: 20,
                button: true,
            )
        let states: [(String, GlassConfig)] = [
            ("IDLE", base),
            ("HOVER", base.applyingButtonState(hovered: true, pressed: false)),
            ("PRESS", base.applyingButtonState(hovered: false, pressed: true)),
        ]
        for (index, entry) in states.enumerated() {
            let frame = LGRect(x: 64 + Double(index) * 264, y: 112, width: 216, height: 96)
            scene.layers.append(SceneLayer(
                kind: .image(RGBAImage(width: 0, height: 0)),
                frame: frame,
                traits: StackingTraits(positionIsStatic: false, zIndex: index + 1, domIndex: index + 1),
                glassConfig: entry.1
            ))
            scene.glassIndices.append(scene.layers.count - 1)
            _ = entry.0
        }
        return scene
    }

    /// Two panels where one overlaps the other, showing layered refraction:
    /// the upper panel bends the lower panel's already-shaded output.
    public static let overlap = DemoScene(
        name: "overlap",
        summary: "Two overlapping panels, layered refraction"
    ) { scale in
        let size = LGSize(width: 900, height: 560)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.spectrum(size: size, scale: scale, bands: 9), frame: LGRect(origin: .zero, size: size)))

        let lower = LGRect(x: 120, y: 300, width: 340, height: 180)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: lower,
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(
                blurAmount: 0.20,
                refraction: 0.55,
                cornerRadius: 34,
                zRadius: 26,
                tintStrength: 0.08,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)

        let upper = LGRect(x: 380, y: 110, width: 360, height: 190)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: upper,
            traits: StackingTraits(positionIsStatic: false, zIndex: 2, domIndex: 2),
            glassConfig: GlassConfig(
                blurAmount: 0.30,
                refraction: 0.48,
                cornerRadius: 40,
                zRadius: 30,
                shadowOpacity: 0.34,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)
        return scene
    }

    /// A row of small chips at different refraction strengths, so the effect of
    /// each parameter is directly comparable.
    public static let panelRow = DemoScene(
        name: "panel-row",
        summary: "Chips sweeping refraction strength"
    ) { scale in
        let size = LGSize(width: 960, height: 360)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.grid(size: size, scale: scale, cell: 22, labelEvery: 0), frame: LGRect(origin: .zero, size: size)))

        for index in 0..<5 {
            let refraction = 0.15 + Double(index) * 0.28
            let frame = LGRect(x: 48 + Double(index) * 180, y: 128, width: 148, height: 104)
            scene.layers.append(SceneLayer(
                kind: .image(RGBAImage(width: 0, height: 0)),
                frame: frame,
                traits: StackingTraits(positionIsStatic: false, zIndex: index + 1, domIndex: index + 1),
                glassConfig: GlassConfig(
                blurAmount: 0.10,
                refraction: refraction,
                edgeHighlight: 0.08,
                cornerRadius: 28,
                zRadius: 24,
            )
            ))
            scene.glassIndices.append(scene.layers.count - 1)
        }
        return scene
    }

    /// Chromatic dispersion over high-frequency colour bands.
    public static let spectrumRefraction = DemoScene(
        name: "spectrum-refraction",
        summary: "Chromatic aberration over colour bands"
    ) { scale in
        let size = LGSize(width: 900, height: 420)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.spectrum(size: size, scale: scale, bands: 5), frame: LGRect(origin: .zero, size: size)))
        let frame = LGRect(x: 190, y: 110, width: 520, height: 200)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: frame,
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(
                blurAmount: 0,
                refraction: 0.85,
                chromAberration: 0.22,
                edgeHighlight: 0.12,
                cornerRadius: 60,
                zRadius: 46,
                shadowOpacity: 0.26,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)
        return scene
    }

    /// Specular highlights over a dark, high-contrast backdrop.
    public static let starfieldSpecular = DemoScene(
        name: "starfield-specular",
        summary: "Specular highlights over a dark starfield"
    ) { scale in
        let size = LGSize(width: 900, height: 520)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.starfield(size: size, scale: scale, seed: 0x51A7), frame: LGRect(origin: .zero, size: size)))
        let frame = LGRect(x: 250, y: 150, width: 400, height: 220)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: frame,
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(
                blurAmount: 0.06,
                refraction: 0.6,
                edgeHighlight: 0.16,
                specular: 0.85,
                fresnel: 1.0,
                cornerRadius: 46,
                zRadius: 38,
                shadowOpacity: 0.5,
                shadowSpread: 22,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)
        return scene
    }

    /// The magnifier parameter comparison: biconvex vs dome over the same text.
    public static let magnifierOnly = DemoScene(
        name: "bevel-modes",
        summary: "Biconvex vs dome bevel over the same content"
    ) { scale in
        let size = LGSize(width: 880, height: 460)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(labelLayer(size: size, scale: scale, title: "REFRACTION", subtitle: "BICONVEX LEFT  DOME RIGHT"), frame: LGRect(origin: .zero, size: size)))

        let left = LGRect(x: 96, y: 190, width: 300, height: 200)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: left,
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(
                blurAmount: 0,
                refraction: 0.8,
                cornerRadius: 40,
                zRadius: 34,
                bevelMode: .biconvex,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)

        let right = LGRect(x: 484, y: 190, width: 300, height: 200)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: right,
            traits: StackingTraits(positionIsStatic: false, zIndex: 2, domIndex: 2),
            glassConfig: GlassConfig(
                blurAmount: 0,
                refraction: 0.8,
                cornerRadius: 100,
                zRadius: 100,
                bevelMode: .dome,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)
        return scene
    }

    /// A large surface, the shape a menu or sidebar takes. Lower refraction
    /// values keep large panels from looking like funhouse mirrors.
    public static let bezelComparison = DemoScene(
        name: "bezel-width",
        summary: "Bevel depth sweep over a grid"
    ) { scale in
        let size = LGSize(width: 960, height: 380)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.grid(size: size, scale: scale, cell: 24, labelEvery: 0), frame: LGRect(origin: .zero, size: size)))
        for index in 0..<4 {
            let zRadius = 8.0 + Double(index) * 22
            let frame = LGRect(x: 56 + Double(index) * 224, y: 120, width: 184, height: 140)
            scene.layers.append(SceneLayer(
                kind: .image(RGBAImage(width: 0, height: 0)),
                frame: frame,
                traits: StackingTraits(positionIsStatic: false, zIndex: index + 1, domIndex: index + 1),
                glassConfig: GlassConfig(
                blurAmount: 0,
                refraction: 0.6,
                cornerRadius: 30,
                zRadius: zRadius,
            )
            ))
            scene.glassIndices.append(scene.layers.count - 1)
        }
        return scene
    }

    /// A full-width glass sheet — the "large surface" case, with a gentle
    /// refraction so text behind it stays readable.
    public static let largeSurface = DemoScene(
        name: "large-surface",
        summary: "Full-width glass sheet over a mesh gradient"
    ) { scale in
        let size = LGSize(width: 1000, height: 560)
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(Wallpaper.mesh(size: size, scale: scale, seed: 0xC0FFEE, blobs: 9), frame: LGRect(origin: .zero, size: size)))
        scene.layers.append(.image(labelLayer(size: size, scale: scale, title: "SIDEBAR", subtitle: "LARGE SURFACE  LOW REFRACTION"), frame: LGRect(origin: .zero, size: size)))
        let frame = LGRect(x: 60, y: 60, width: 880, height: 440)
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: frame,
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(
                blurAmount: 0.34,
                refraction: 0.30,
                cornerRadius: 28,
                zRadius: 22,
                tintStrength: 0.06,
                shadowOpacity: 0.24,
                shadowSpread: 18,
                shadowOffsetY: 6,
            )
        ))
        scene.glassIndices.append(scene.layers.count - 1)
        return scene
    }

    /// The `.nativeBlur` path the SwiftUI and AppKit layers use on Ventura.
    ///
    /// With no backdrop to sample, those layers hand the renderer a 1x1 black
    /// image and composite the result additively over the system blur, so only
    /// the lighting terms survive. That stand-in used to collapse the whole
    /// render to a single pixel, which flattened the rim and specular gradient
    /// on every surface that used it. This scene reproduces the pass, so the
    /// image would be a flat black rectangle if the bug came back.
    public static let nativeBlurLighting = DemoScene(
        name: "native-blur-lighting",
        summary: "The backdrop-independent lighting pass, composited over a blur"
    ) { scale in
        let size = LGSize(width: 900, height: 420)
        let config = GlassConfig(
            blurAmount: 0,
            refraction: 0.62,
            chromAberration: 0.12,
            edgeHighlight: 0.6,
            specular: 0.75,
            fresnel: 0.9,
            cornerRadius: 40,
            zRadius: 36,
            shadowOpacity: 0
        )

        // A representative slice of a mesh gradient, blurred hard and dimmed,
        // standing in for what `NSVisualEffectView` puts behind the panel. It
        // is dimmed so the additive lighting below stays in range instead of
        // saturating to white.
        var backdrop = Wallpaper.mesh(size: size, scale: scale, seed: 0xB10B, blobs: 7)
        backdrop = SoftwareGlassRenderer.blur(backdrop, amount: 1.0)
        for y in 0..<backdrop.height {
            for x in 0..<backdrop.width {
                let c = backdrop.color(x: x, y: y)
                backdrop.setColor(x: x, y: y, RGBAColor(r: c.r * 0.22, g: c.g * 0.22, b: c.b * 0.24, a: 1))
            }
        }

        // The panel is rendered against a 1x1 black stand-in and added on top.
        let frame = LGRect(x: 150, y: 90, width: 600, height: 240)
        let pad = glassShadowPad
        let boxW = Int(((frame.width + pad * 2) * scale).rounded())
        let boxH = Int(((frame.height + pad * 2) * scale).rounded())
        let stand_in = RGBAImage(width: 1, height: 1, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        let lighting = SoftwareGlassRenderer(backdrop: stand_in)
            .renderPanel(config: config, size: frame.size, scale: scale)

        var canvas = RGBAImage(width: backdrop.width, height: backdrop.height)
        canvas.composite(backdrop, at: LGPoint(x: 0, y: 0))
        let origin = LGPoint(
            x: (frame.x - pad) * scale,
            y: (frame.y - pad) * scale
        )
        // Additive, matching `CGBlendMode.plusLighter` in the AppKit layer.
        for y in 0..<boxH {
            for x in 0..<boxW {
                let ty = Int(origin.y) + y
                let tx = Int(origin.x) + x
                guard ty >= 0, ty < canvas.height, tx >= 0, tx < canvas.width else { continue }
                let src = lighting.color(x: x, y: y)
                let dst = canvas.color(x: tx, y: ty)
                canvas.setColor(x: tx, y: ty, RGBAColor(
                    r: min(dst.r + src.r * src.a, 1),
                    g: min(dst.g + src.g * src.a, 1),
                    b: min(dst.b + src.b * src.a, 1),
                    a: 1
                ))
            }
        }
        var scene = GlassScene(bounds: LGRect(origin: .zero, size: size), scale: scale)
        scene.layers.append(.image(canvas, frame: LGRect(origin: .zero, size: size)))
        return scene
    }

    // MARK: - Helpers

    /// A transparent layer carrying only text, so labels sit behind the glass
    /// and get bent by it.
    private static func labelLayer(size: LGSize, scale: Double, title: String, subtitle: String) -> RGBAImage {
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        var image = RGBAImage(width: w, height: h)
        let textScale = max(Int(scale * 2), 2)
        let titleSize = TextRasterizer.measure(title, scale: textScale)
        TextRasterizer.draw(
            title,
            into: &image,
            at: LGPoint(x: (Double(w) - titleSize.width) / 2, y: Double(h) * 0.72),
            color: RGBAColor(r: 1, g: 1, b: 1, a: 0.92),
            scale: textScale
        )
        let subScale = max(Int(scale), 1)
        let subSize = TextRasterizer.measure(subtitle, scale: subScale)
        TextRasterizer.draw(
            subtitle,
            into: &image,
            at: LGPoint(x: (Double(w) - subSize.width) / 2, y: Double(h) * 0.72 + titleSize.height + 8 * scale),
            color: RGBAColor(r: 1, g: 1, b: 1, a: 0.65),
            scale: subScale
        )
        return image
    }
}
