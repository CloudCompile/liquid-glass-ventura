import XCTest
@testable import LiquidGlassCore

final class ImageTests: XCTestCase {

    private func makeImage(_ width: Int, _ height: Int) -> RGBAImage {
        var image = RGBAImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                image.setColor(x: x, y: y, RGBAColor(
                    r: Double(x) / Double(max(width - 1, 1)),
                    g: Double(y) / Double(max(height - 1, 1)),
                    b: 0.5,
                    a: 1
                ))
            }
        }
        return image
    }

    func testFillSetsEveryPixel() {
        let image = RGBAImage(width: 4, height: 3, fill: RGBAColor(r: 1, g: 0, b: 0, a: 1))
        for y in 0..<3 {
            for x in 0..<4 {
                XCTAssertEqual(image.color(x: x, y: y).r, 1)
            }
        }
    }

    func testOutOfBoundsReadsReturnClear() {
        let image = RGBAImage(width: 2, height: 2, fill: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        XCTAssertEqual(image.color(x: -1, y: 0), .clear)
        XCTAssertEqual(image.color(x: 0, y: 5), .clear)
    }

    func testBilinearSampleReturnsExactPixelAtCentre() {
        let image = makeImage(4, 4)
        let c = image.sampleBilinear(x: 2.5, y: 2.5)
        XCTAssertEqual(c.r, image.color(x: 2, y: 2).r, accuracy: 1e-9)
        XCTAssertEqual(c.g, image.color(x: 2, y: 2).g, accuracy: 1e-9)
    }

    func testBilinearSampleInterpolatesBetweenPixels() {
        let image = makeImage(4, 4)
        let c = image.sampleBilinear(x: 1.0, y: 0.5)
        // Halfway between pixel 0 and pixel 1 on the top row.
        let expected = (image.color(x: 0, y: 0).r + image.color(x: 1, y: 0).r) / 2
        XCTAssertEqual(c.r, expected, accuracy: 1e-9)
    }

    func testBilinearSampleClampsAtEdges() {
        let image = makeImage(4, 4)
        let c = image.sampleBilinear(x: -50, y: -50)
        XCTAssertEqual(c.r, image.color(x: 0, y: 0).r, accuracy: 1e-9)
    }

    func testCropExtractsTheRequestedRegion() {
        let image = makeImage(8, 8)
        let crop = image.cropped(to: LGRect(x: 2, y: 3, width: 4, height: 2))
        XCTAssertEqual(crop.width, 4)
        XCTAssertEqual(crop.height, 2)
        XCTAssertEqual(crop.color(x: 0, y: 0).r, image.color(x: 2, y: 3).r, accuracy: 1e-9)
        XCTAssertEqual(crop.color(x: 3, y: 1).r, image.color(x: 5, y: 4).r, accuracy: 1e-9)
    }

    func testCropFillsOutOfBoundsWithTheGivenColour() {
        let image = makeImage(4, 4)
        let crop = image.cropped(
            to: LGRect(x: -2, y: -2, width: 4, height: 4),
            outOfBounds: RGBAColor(r: 1, g: 1, b: 1, a: 1)
        )
        XCTAssertEqual(crop.color(x: 0, y: 0).r, 1)
        XCTAssertEqual(crop.color(x: 0, y: 0).a, 1)
    }

    func testCompositeOpaqueSourceOverwrites() {
        var base = RGBAImage(width: 4, height: 4, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        let patch = RGBAImage(width: 2, height: 2, fill: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        base.composite(patch, at: LGPoint(x: 1, y: 1))
        XCTAssertEqual(base.color(x: 1, y: 1).r, 1)
        XCTAssertEqual(base.color(x: 2, y: 2).r, 1)
        XCTAssertEqual(base.color(x: 0, y: 0).r, 0)
        XCTAssertEqual(base.color(x: 3, y: 3).r, 0)
    }

    func testCompositeClipsToBounds() {
        var base = RGBAImage(width: 4, height: 4, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        let patch = RGBAImage(width: 3, height: 3, fill: RGBAColor(r: 1, g: 1, b: 1, a: 1))
        base.composite(patch, at: LGPoint(x: 3, y: 3))
        XCTAssertEqual(base.color(x: 3, y: 3).r, 1)
        // Everything else stays background; nothing crashed or wrapped.
        XCTAssertEqual(base.color(x: 0, y: 0).r, 0)
    }

    func testCompositeSkipsFullyTransparentSource() {
        var base = RGBAImage(width: 2, height: 2, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        let patch = RGBAImage(width: 2, height: 2, fill: .clear)
        base.composite(patch, at: .zero)
        XCTAssertEqual(base.color(x: 0, y: 0).r, 0)
        XCTAssertEqual(base.color(x: 0, y: 0).a, 1)
    }

    func testCompositeBlendsTranslucentSource() {
        var base = RGBAImage(width: 2, height: 2, fill: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        let patch = RGBAImage(width: 2, height: 2, fill: RGBAColor(r: 1, g: 1, b: 1, a: 0.5))
        base.composite(patch, at: .zero)
        XCTAssertEqual(base.color(x: 0, y: 0).r, 0.5, accuracy: 1.0 / 255.0)
    }

    func testRoundedToPixelsScalesAndRounds() {
        let r = LGRect(x: 10.4, y: 20.6, width: 30.2, height: 40.9).roundedToPixels(scale: 2)
        XCTAssertEqual(r.x, 21)
        XCTAssertEqual(r.y, 41)
        XCTAssertEqual(r.width, 60)
        XCTAssertEqual(r.height, 82)
    }
}
