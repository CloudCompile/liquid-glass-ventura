import XCTest
@testable import LiquidGlassCore

final class GlassConfigTests: XCTestCase {

    func testDefaultsMatchTheReferenceLibrary() {
        // Values copied from the reference `defaults.ts`. If the port ever
        // drifts, this test is the first thing that fails.
        let c = GlassConfig.standard
        XCTAssertEqual(c.blurAmount, 0)
        XCTAssertEqual(c.refraction, 0.69)
        XCTAssertEqual(c.chromAberration, 0.05)
        XCTAssertEqual(c.edgeHighlight, 0.05)
        XCTAssertEqual(c.specular, 0)
        XCTAssertEqual(c.fresnel, 1)
        XCTAssertEqual(c.distortion, 0)
        XCTAssertEqual(c.cornerRadius, 65)
        XCTAssertEqual(c.zRadius, 40)
        XCTAssertEqual(c.opacity, 1)
        XCTAssertEqual(c.saturation, 0)
        XCTAssertEqual(c.tintStrength, 0)
        XCTAssertEqual(c.brightness, 0)
        XCTAssertEqual(c.shadowOpacity, 0.3)
        XCTAssertEqual(c.shadowSpread, 10)
        XCTAssertEqual(c.shadowOffsetY, 1)
        XCTAssertFalse(c.floating)
        XCTAssertFalse(c.button)
        XCTAssertEqual(c.bevelMode, .biconvex)
        XCTAssertNil(c.tintColor)
    }

    func testBevelModeRawValuesMatchTheReference() {
        // The web library encodes the bevel mode as an integer in JSON.
        XCTAssertEqual(GlassBevelMode.biconvex.rawValue, 0)
        XCTAssertEqual(GlassBevelMode.dome.rawValue, 1)
    }

    func testOverridingAppliesOnlyChangedValues() {
        let base = GlassConfig(blurAmount: 0.5, refraction: 0.3, cornerRadius: 20)
        // `other` leaves refraction at the library default, so it must not
        // clobber the base's explicit 0.3.
        let other = GlassConfig(cornerRadius: 44)
        let merged = base.overriding(with: other)
        XCTAssertEqual(merged.blurAmount, 0.5)
        XCTAssertEqual(merged.refraction, 0.3)
        XCTAssertEqual(merged.cornerRadius, 44)
    }

    func testOverridingTakesNonDefaultValues() {
        let merged = GlassConfig.standard.overriding(with: GlassConfig(blurAmount: 0.75, refraction: 0.9))
        XCTAssertEqual(merged.blurAmount, 0.75)
        XCTAssertEqual(merged.refraction, 0.9)
    }

    func testOverridingCopiesTintColorOnlyWhenSet() {
        let tinted = GlassConfig.standard.overriding(with: GlassConfig(tintColor: RGBColor(hex: 0xFF0000)))
        XCTAssertEqual(tinted.tintColor, RGBColor(hex: 0xFF0000))

        let untouched = GlassConfig(tintColor: RGBColor(hex: 0x00FF00))
            .overriding(with: GlassConfig(blurAmount: 0.2))
        XCTAssertEqual(untouched.tintColor, RGBColor(hex: 0x00FF00))
    }

    func testButtonPressFlattensBevelAndWidensShadow() {
        let button = GlassConfig(zRadius: 40, shadowSpread: 10, button: true)
        let pressed = button.applyingButtonState(hovered: false, pressed: true)
        XCTAssertEqual(pressed.zRadius, 32, accuracy: 1e-12)
        XCTAssertEqual(pressed.shadowSpread, 12, accuracy: 1e-12)
    }

    func testButtonHoverLiftsBrightness() {
        let button = GlassConfig(brightness: 0.1, button: true)
        let hovered = button.applyingButtonState(hovered: true, pressed: false)
        XCTAssertEqual(hovered.brightness, 0.3, accuracy: 1e-12)
    }

    func testPressTakesPrecedenceOverHover() {
        let button = GlassConfig(zRadius: 40, brightness: 0.1, button: true)
        let both = button.applyingButtonState(hovered: true, pressed: true)
        XCTAssertEqual(both.brightness, 0.1, accuracy: 1e-12)
        XCTAssertEqual(both.zRadius, 32, accuracy: 1e-12)
    }

    func testNonButtonConfigIsUnchangedByState() {
        let surface = GlassConfig(zRadius: 40, button: false)
        XCTAssertEqual(surface.applyingButtonState(hovered: true, pressed: true), surface)
    }

    func testReferenceAlphaCompositingDefaultsToFaithfulPort() {
        XCTAssertTrue(GlassConfig.standard.referenceAlphaCompositing)
    }
}
