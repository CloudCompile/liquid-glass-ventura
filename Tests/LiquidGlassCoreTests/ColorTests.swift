import XCTest
@testable import LiquidGlassCore

final class ColorTests: XCTestCase {

    func testOverWithOpaqueSourceReplacesBackdrop() {
        let src = RGBAColor(r: 1, g: 0, b: 0, a: 1)
        let dst = RGBAColor(r: 0, g: 0, b: 1, a: 1)
        XCTAssertEqual(src.over(dst), src)
    }

    func testOverWithTransparentSourceKeepsBackdrop() {
        let dst = RGBAColor(r: 0, g: 1, b: 0, a: 1)
        let out = RGBAColor(r: 1, g: 0, b: 0, a: 0).over(dst)
        XCTAssertEqual(out.r, dst.r, accuracy: 1e-12)
        XCTAssertEqual(out.g, dst.g, accuracy: 1e-12)
        XCTAssertEqual(out.b, dst.b, accuracy: 1e-12)
    }

    func testOverBlendsHalfway() {
        let src = RGBAColor(r: 0, g: 0, b: 0, a: 0.5)
        let dst = RGBAColor(r: 1, g: 1, b: 1, a: 1)
        let out = src.over(dst)
        XCTAssertEqual(out.r, 0.5, accuracy: 1e-12)
        XCTAssertEqual(out.a, 1, accuracy: 1e-12)
    }

    func testOverOnTwoTranslucentLayers() {
        // 0.5 over 0.5 gives alpha 0.75 and a 1:1 average of the two colours.
        let src = RGBAColor(r: 1, g: 0, b: 0, a: 0.5)
        let dst = RGBAColor(r: 0, g: 0, b: 1, a: 0.5)
        let out = src.over(dst)
        XCTAssertEqual(out.a, 0.75, accuracy: 1e-12)
        XCTAssertEqual(out.r, 2.0 / 3.0, accuracy: 1e-12)
        XCTAssertEqual(out.b, 1.0 / 3.0, accuracy: 1e-12)
    }

    func testLuminanceUsesReferenceCoefficients() {
        XCTAssertEqual(RGBColor.white.luminance, 1, accuracy: 1e-12)
        XCTAssertEqual(RGBColor.black.luminance, 0, accuracy: 1e-12)
        XCTAssertEqual(RGBColor(r: 1, g: 0, b: 0).luminance, 0.299, accuracy: 1e-12)
        XCTAssertEqual(RGBColor(r: 0, g: 1, b: 0).luminance, 0.587, accuracy: 1e-12)
        XCTAssertEqual(RGBColor(r: 0, g: 0, b: 1).luminance, 0.114, accuracy: 1e-12)
    }

    func testHexInitParsesChannels() {
        let c = RGBColor(hex: 0x336699)
        XCTAssertEqual(c.r, 0x33 / 255.0, accuracy: 1e-12)
        XCTAssertEqual(c.g, 0x66 / 255.0, accuracy: 1e-12)
        XCTAssertEqual(c.b, 0x99 / 255.0, accuracy: 1e-12)
    }

    func testClampedBoundsChannels() {
        let c = RGBColor(r: -1, g: 2, b: 0.5).clamped()
        XCTAssertEqual(c.r, 0)
        XCTAssertEqual(c.g, 1)
        XCTAssertEqual(c.b, 0.5)
    }

    func testMixedInterpolatesAndClampsAmount() {
        let a = RGBColor.black
        let b = RGBColor.white
        XCTAssertEqual(a.mixed(with: b, amount: 0.25).r, 0.25, accuracy: 1e-12)
        XCTAssertEqual(a.mixed(with: b, amount: 5).r, 1, accuracy: 1e-12)
        XCTAssertEqual(a.mixed(with: b, amount: -5).r, 0, accuracy: 1e-12)
    }

    func testRGBAColorMixedInterpolatesAlphaToo() {
        let a = RGBAColor(r: 0, g: 0, b: 0, a: 0)
        let b = RGBAColor(r: 1, g: 1, b: 1, a: 1)
        let m = a.mixed(with: b, amount: 0.5)
        XCTAssertEqual(m.a, 0.5, accuracy: 1e-12)
        XCTAssertEqual(m.r, 0.5, accuracy: 1e-12)
    }
}
