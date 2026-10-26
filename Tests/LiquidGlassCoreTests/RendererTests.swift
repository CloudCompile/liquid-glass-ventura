import XCTest
@testable import LiquidGlassCore

final class RendererTests: XCTestCase {

    private func flatBackdrop(_ width: Int, _ height: Int, color: RGBAColor) -> RGBAImage {
        RGBAImage(width: width, height: height, fill: color)
    }

    func testPanelCentreSamplesBackdropWithOnlyTheDepthGain() {
        // No blur, no refraction, no tint: the middle of the panel is a plain
        // window onto the backdrop, modulated only by the shader's depth gain
        // (`col *= 1 + 0.06 * depth`, which saturates at the panel centre).
        let backdrop = flatBackdrop(200, 120, color: RGBAColor(r: 0.2, g: 0.4, b: 0.8, a: 1))
        let renderer = SoftwareGlassRenderer(backdrop: backdrop)
        let config = GlassConfig(
            blurAmount: 0,
            refraction: 0,
            cornerRadius: 10,
            zRadius: 10,
            shadowOpacity: 0,
            referenceAlphaCompositing: false
        )
        let panel = renderer.renderPanel(config: config, size: LGSize(width: 100, height: 60), scale: 2)
        let centre = panel.color(x: panel.width / 2, y: panel.height / 2)
        XCTAssertEqual(centre.r, 0.2 * 1.06, accuracy: 0.02)
        XCTAssertEqual(centre.g, 0.4 * 1.06, accuracy: 0.02)
        XCTAssertEqual(centre.b, 0.8 * 1.06, accuracy: 0.02)
        XCTAssertEqual(centre.a, 1, accuracy: 0.01)
    }

    func testPanelInteriorIsOpaque() {
        let backdrop = flatBackdrop(200, 120, color: RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 1))
        let renderer = SoftwareGlassRenderer(backdrop: backdrop)
        let config = GlassConfig(cornerRadius: 12, zRadius: 12, shadowOpacity: 0)
        let panel = renderer.renderPanel(config: config, size: LGSize(width: 100, height: 60), scale: 2)
        XCTAssertEqual(panel.color(x: panel.width / 2, y: panel.height / 2).a, 1, accuracy: 0.02)
    }

    func testCornersAreClippedByTheRoundedRect() {
        let backdrop = flatBackdrop(200, 120, color: RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 1))
        let renderer = SoftwareGlassRenderer(backdrop: backdrop)
        let config = GlassConfig(cornerRadius: 40, zRadius: 20, shadowOpacity: 0)
        let panel = renderer.renderPanel(config: config, size: LGSize(width: 100, height: 60), scale: 2)
        // The very corner of the padded canvas is outside the rounded rect.
        XCTAssertLessThan(panel.color(x: 1, y: 1).a, 0.5)
    }

    func testOpacityScalesPanelAlpha() {
        let backdrop = flatBackdrop(200, 120, color: RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 1))
        let renderer = SoftwareGlassRenderer(backdrop: backdrop)
        let config = GlassConfig(cornerRadius: 10, zRadius: 10, opacity: 0.5, shadowOpacity: 0)
        let panel = renderer.renderPanel(config: config, size: LGSize(width: 100, height: 60), scale: 2)
        XCTAssertEqual(panel.color(x: panel.width / 2, y: panel.height / 2).a, 0.5, accuracy: 0.02)
    }

    func testShadowDarkensOutsideThePanel() {
        let backdrop = flatBackdrop(240, 160, color: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        let renderer = SoftwareGlassRenderer(backdrop: backdrop)
        let config = GlassConfig(cornerRadius: 10, zRadius: 10, shadowOpacity: 0.8, shadowSpread: 20)
        let panel = renderer.renderPanel(config: config, size: LGSize(width: 100, height: 60), scale: 2)
        // Just below the bottom edge, inside the shadow padding.
        let pad = glassShadowPad * 2
        let sampleY = Int(pad + 60 * 2 + 4)
        let sample = panel.color(x: panel.width / 2, y: min(sampleY, panel.height - 1))
        XCTAssertGreaterThan(sample.a, 0.01)
        XCTAssertLessThan(sample.a, 0.99)
    }

    func testShadowAlphaIsTheShaderValueNotSquared() {
        // The shader writes `shadowOpacity * profile` straight into the alpha
        // channel; the squaring the reference library exhibits happens later,
        // in its canvas compositing (see `RGBAColor.referenceOver`), not here.
        // The backdrop must be the padded panel box, or the panel would fill
        // it edge to edge and the shadow would have nowhere to land.
        let backdrop = flatBackdrop(280, 200, color: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        let panel = SoftwareGlassRenderer(backdrop: backdrop).renderPanel(
            config: GlassConfig(cornerRadius: 10, zRadius: 10, shadowOpacity: 0.8, shadowSpread: 20),
            size: LGSize(width: 100, height: 60),
            scale: 2
        )
        // Just below the panel edge the shadow profile is still near its peak,
        // so the stored alpha must be well above zero and below the peak
        // product, never the square of it.
        let y = Int(glassShadowPad * 2 + 60 * 2 + 4)
        let alpha = panel.color(x: 120, y: y).a
        XCTAssertGreaterThan(alpha, 0.1)
        XCTAssertLessThanOrEqual(alpha, 0.8 + 1e-6)
    }

    func testReferenceOverSquaresCoverageButNotColour() {
        // A translucent white over black, the way the reference library's
        // canvas blend behaves.
        let panel = RGBAColor(r: 1, g: 1, b: 1, a: 0.5)
        let backdrop = RGBAColor(r: 0, g: 0, b: 0, a: 1)
        let out = panel.referenceOver(backdrop)
        // The canvas stores `rgb * 0.5` with coverage `0.25`, and the browser
        // composites that premultiplied value over the opaque black backdrop,
        // leaving a half-strength white.
        XCTAssertEqual(out.a, 1, accuracy: 1e-12)
        XCTAssertEqual(out.r, 0.5, accuracy: 1e-12)
    }

    func testBlurReducesLocalVariance() {
        // A noisy backdrop must come out smoother after blurring.
        var noise = RGBAImage(width: 64, height: 64)
        var rng = SplitMix64(seed: 7)
        for y in 0..<64 {
            for x in 0..<64 {
                let v = rng.unit()
                noise.setColor(x: x, y: y, RGBAColor(r: v, g: v, b: v, a: 1))
            }
        }
        let blurred = SoftwareGlassRenderer.blur(noise, amount: 0.5)
        XCTAssertLessThan(variance(blurred), variance(noise))
    }

    func testBlurWithZeroAmountIsIdentity() {
        var image = RGBAImage(width: 8, height: 8)
        image.setColor(x: 3, y: 3, RGBAColor(r: 1, g: 0, b: 0, a: 1))
        XCTAssertEqual(SoftwareGlassRenderer.blur(image, amount: 0), image)
    }

    func testBlurPreservesFlatImages() {
        let flat = flatBackdrop(32, 32, color: RGBAColor(r: 0.3, g: 0.6, b: 0.9, a: 1))
        let blurred = SoftwareGlassRenderer.blur(flat, amount: 0.8)
        let c = blurred.color(x: 16, y: 16)
        XCTAssertEqual(c.r, 0.3, accuracy: 0.01)
        XCTAssertEqual(c.g, 0.6, accuracy: 0.01)
        XCTAssertEqual(c.b, 0.9, accuracy: 0.01)
    }

    func testRenderPanelReturnsAnImageTheSizeOfTheBackdrop() {
        // `renderPanel` shades the whole padded backdrop it is handed; the
        // caller is responsible for cropping the scene to
        // `panelSize + 2 * glassShadowPad` first (see `GlassScene.shadeGlass`).
        let paddedWidth = Int(100 * 2 + glassShadowPad * 2 * 2)
        let paddedHeight = Int(60 * 2 + glassShadowPad * 2 * 2)
        let backdrop = flatBackdrop(paddedWidth, paddedHeight, color: RGBAColor(r: 0.5, g: 0.5, b: 0.5, a: 1))
        let panel = SoftwareGlassRenderer(backdrop: backdrop)
            .renderPanel(config: .standard, size: LGSize(width: 100, height: 60), scale: 2)
        XCTAssertEqual(panel.width, paddedWidth)
        XCTAssertEqual(panel.height, paddedHeight)
    }

    // A 1x1 backdrop is how a flat colour is passed in: the `.color` backdrop,
    // and the black stand-in the AppKit layer uses when the lighting is
    // composited over the system blur. The panel's geometry comes from `size`
    // and `scale`, so the output must be the padded box, not one pixel.
    func testFlatColourBackdropRendersTheWholePaddedBox() {
        let size = LGSize(width: 200, height: 80)
        let scale = 2.0
        let flat = RGBAImage(width: 1, height: 1, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        let panel = SoftwareGlassRenderer(backdrop: flat)
            .renderPanel(config: .standard, size: size, scale: scale)

        let pad = glassShadowPad
        XCTAssertEqual(panel.width, Int((size.width + pad * 2) * scale))
        XCTAssertEqual(panel.height, Int((size.height + pad * 2) * scale))
    }

    /// The lighting must vary across the panel. Before the fix the 1x1
    /// backdrop collapsed the render to a single pixel, so every surface drew
    /// one flat colour and the rim and specular highlights disappeared.
    func testFlatColourBackdropKeepsTheLightingGradient() {
        let size = LGSize(width: 200, height: 80)
        let flat = RGBAImage(width: 1, height: 1, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        var config = GlassConfig.standard
        config.shadowOpacity = 0
        let panel = SoftwareGlassRenderer(backdrop: flat)
            .renderPanel(config: config, size: size, scale: 2)

        XCTAssertGreaterThan(variance(panel), 0.0001, "the rim and specular gradient collapsed to a flat colour")

        // And the brightest point must beat the darkest by a clear margin.
        var lo = 1.0
        var hi = 0.0
        for y in 0..<panel.height {
            for x in 0..<panel.width {
                let v = panel.color(x: x, y: y).r
                lo = min(lo, v)
                hi = max(hi, v)
            }
        }
        XCTAssertGreaterThan(hi - lo, 0.1)
    }

    /// The flat-colour expansion must agree with an explicitly sized backdrop
    /// of the same colour, which is the case the rest of the suite covers.
    func testFlatColourBackdropMatchesAnExplicitlySizedOne() {
        let size = LGSize(width: 120, height: 60)
        let scale = 2.0
        let pad = glassShadowPad
        let boxW = Int((size.width + pad * 2) * scale)
        let boxH = Int((size.height + pad * 2) * scale)
        let colour = RGBAColor(r: 0.25, g: 0.5, b: 0.75, a: 1)

        var config = GlassConfig.standard
        config.shadowOpacity = 0.3
        let flat = SoftwareGlassRenderer(backdrop: RGBAImage(width: 1, height: 1, fill: colour))
            .renderPanel(config: config, size: size, scale: scale)
        let explicit = SoftwareGlassRenderer(backdrop: RGBAImage(width: boxW, height: boxH, fill: colour))
            .renderPanel(config: config, size: size, scale: scale)

        XCTAssertEqual(flat.width, explicit.width)
        XCTAssertEqual(flat.height, explicit.height)
        for y in stride(from: 0, to: explicit.height, by: 7) {
            for x in stride(from: 0, to: explicit.width, by: 7) {
                let a = flat.color(x: x, y: y)
                let b = explicit.color(x: x, y: y)
                XCTAssertEqual(a.r, b.r, accuracy: 1.0 / 255)
                XCTAssertEqual(a.g, b.g, accuracy: 1.0 / 255)
                XCTAssertEqual(a.b, b.b, accuracy: 1.0 / 255)
                XCTAssertEqual(a.a, b.a, accuracy: 1.0 / 255)
            }
        }
    }

    private func variance(_ image: RGBAImage) -> Double {
        var sum = 0.0
        var sumSq = 0.0
        var count = 0.0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let v = image.color(x: x, y: y).r
                sum += v
                sumSq += v * v
                count += 1
            }
        }
        let mean = sum / count
        return sumSq / count - mean * mean
    }
}
