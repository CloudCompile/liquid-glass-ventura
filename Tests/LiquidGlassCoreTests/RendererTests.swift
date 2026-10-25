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
