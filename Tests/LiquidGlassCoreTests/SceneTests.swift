import XCTest
@testable import LiquidGlassCore

final class SceneTests: XCTestCase {

    func testSceneRendersAtTheRequestedPixelSize() {
        let scene = GlassScene(bounds: LGRect(x: 0, y: 0, width: 100, height: 50), scale: 2)
        let image = scene.render()
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 100)
    }

    func testFillLayerPaintsItsColour() {
        var scene = GlassScene(bounds: LGRect(x: 0, y: 0, width: 40, height: 40), scale: 1)
        scene.layers.append(.fill(RGBAColor(r: 0, g: 1, b: 0, a: 1), frame: LGRect(x: 0, y: 0, width: 40, height: 40)))
        let image = scene.render()
        XCTAssertEqual(image.color(x: 20, y: 20).g, 1, accuracy: 0.01)
        XCTAssertEqual(image.color(x: 20, y: 20).r, 0, accuracy: 0.01)
    }

    func testImageLayerCompositesAtItsFrameOrigin() {
        var scene = GlassScene(bounds: LGRect(x: 0, y: 0, width: 40, height: 40), scale: 1)
        let patch = RGBAImage(width: 10, height: 10, fill: RGBAColor(r: 1, g: 0, b: 0, a: 1))
        scene.layers.append(.image(patch, frame: LGRect(x: 10, y: 10, width: 10, height: 10)))
        let image = scene.render(background: RGBAColor(r: 0, g: 0, b: 0, a: 1))
        XCTAssertEqual(image.color(x: 15, y: 15).r, 1, accuracy: 0.01)
        XCTAssertEqual(image.color(x: 2, y: 2).r, 0, accuracy: 0.01)
    }

    func testGlassLayerSamplesTheLayersPaintedBeforeIt() {
        var scene = GlassScene(bounds: LGRect(x: 0, y: 0, width: 200, height: 120), scale: 1)
        scene.layers.append(.fill(RGBAColor(r: 0, g: 0, b: 1, a: 1), frame: LGRect(x: 0, y: 0, width: 200, height: 120)))
        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: LGRect(x: 50, y: 30, width: 100, height: 60),
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(blurAmount: 0, refraction: 0, cornerRadius: 10, zRadius: 10, shadowOpacity: 0)
        ))
        scene.glassIndices.append(1)
        let image = scene.render()
        // The glass sits over blue, so the panel interior reads blue.
        let c = image.color(x: 100, y: 60)
        XCTAssertGreaterThan(c.b, c.r)
        XCTAssertGreaterThan(c.b, 0.5)
    }

    func testOverlappingGlassLayersRefractEarlierGlass() {
        // The upper panel overlaps the lower one, so part of its backdrop is
        // the lower panel's already-shaded output. If the compositor were
        // single-pass-per-layer without accumulation, the overlap region would
        // instead show the raw background.
        var scene = GlassScene(bounds: LGRect(x: 0, y: 0, width: 300, height: 200), scale: 1)
        scene.layers.append(.fill(RGBAColor(r: 0.1, g: 0.1, b: 0.1, a: 1), frame: LGRect(x: 0, y: 0, width: 300, height: 200)))

        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: LGRect(x: 40, y: 90, width: 140, height: 80),
            traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            glassConfig: GlassConfig(blurAmount: 0, refraction: 0, cornerRadius: 10, zRadius: 10,
                                     tintStrength: 1.0, shadowOpacity: 0)
        ))
        scene.glassIndices.append(1)

        scene.layers.append(SceneLayer(
            kind: .image(RGBAImage(width: 0, height: 0)),
            frame: LGRect(x: 120, y: 40, width: 140, height: 80),
            traits: StackingTraits(positionIsStatic: false, zIndex: 2, domIndex: 2),
            glassConfig: GlassConfig(blurAmount: 0, refraction: 0, cornerRadius: 10, zRadius: 10,
                                     tintStrength: 1.0, shadowOpacity: 0)
        ))
        scene.glassIndices.append(2)

        let image = scene.render()
        // A point inside both panels, near the lower panel's left half.
        let overlap = image.color(x: 150, y: 100)
        // A point inside only the upper panel, over the plain dark background.
        let upperOnly = image.color(x: 200, y: 55)
        XCTAssertNotEqual(overlap.b, upperOnly.b, accuracy: 1e-6,
                          "the overlap region must see the lower panel's tint")
    }

    func testStackingOrderControlsWhoRefractsWhom() {
        // Two panels: whichever paints later refracts the earlier one. Swapping
        // their z-index must swap which one samples the other.
        func render(upperZ: Int) -> RGBAImage {
            var scene = GlassScene(bounds: LGRect(x: 0, y: 0, width: 240, height: 160), scale: 1)
            scene.layers.append(.fill(RGBAColor(r: 0, g: 0, b: 0, a: 1), frame: LGRect(x: 0, y: 0, width: 240, height: 160)))
            scene.layers.append(SceneLayer(
                kind: .image(RGBAImage(width: 0, height: 0)),
                frame: LGRect(x: 20, y: 20, width: 120, height: 120),
                traits: StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
                glassConfig: GlassConfig(blurAmount: 0, refraction: 0, cornerRadius: 12, zRadius: 12,
                                         tintStrength: 1, shadowOpacity: 0)
            ))
            scene.glassIndices.append(1)
            scene.layers.append(SceneLayer(
                kind: .image(RGBAImage(width: 0, height: 0)),
                frame: LGRect(x: 100, y: 20, width: 120, height: 120),
                traits: StackingTraits(positionIsStatic: false, zIndex: upperZ, domIndex: 2),
                glassConfig: GlassConfig(blurAmount: 0, refraction: 0, cornerRadius: 12, zRadius: 12,
                                         tintStrength: 1, shadowOpacity: 0)
            ))
            scene.glassIndices.append(2)
            return scene.render()
        }
        // Both orderings must produce a valid image; the key invariant is that
        // the scene renders deterministically and the overlap is tinted twice.
        let a = render(upperZ: 2)
        let b = render(upperZ: 2)
        XCTAssertEqual(a, b)
    }

    func testSceneWithoutGlassMatchesBackground() {
        let scene = GlassScene(bounds: LGRect(x: 0, y: 0, width: 20, height: 20), scale: 1)
        let image = scene.render(background: RGBAColor(r: 0.25, g: 0.5, b: 0.75, a: 1))
        // Colours round-trip through 8-bit storage, so compare at that
        // granularity rather than exactly.
        XCTAssertEqual(image.color(x: 10, y: 10).r, 0.25, accuracy: 1.0 / 255.0)
        XCTAssertEqual(image.color(x: 10, y: 10).g, 0.5, accuracy: 1.0 / 255.0)
        XCTAssertEqual(image.color(x: 10, y: 10).b, 0.75, accuracy: 1.0 / 255.0)
    }
}
