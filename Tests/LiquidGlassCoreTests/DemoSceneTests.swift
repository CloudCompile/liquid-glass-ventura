import XCTest
@testable import LiquidGlassCore

/// Guards the shipped demo scenes: they must all render, at the documented
/// size, without crashing or producing an empty image.
final class DemoSceneTests: XCTestCase {

    func testEverySceneHasAUniqueName() {
        let names = DemoScenes.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "scene names must be unique")
    }

    func testEverySceneHasASummary() {
        for scene in DemoScenes.all {
            XCTAssertFalse(scene.summary.isEmpty, "\(scene.name) needs a summary")
        }
    }

    func testEverySceneRendersNonEmptyAtScaleOne() {
        for scene in DemoScenes.all {
            let image = scene.render(scale: 1)
            XCTAssertGreaterThan(image.width, 0, "\(scene.name) rendered no width")
            XCTAssertGreaterThan(image.height, 0, "\(scene.name) rendered no height")
        }
    }

    func testHeroSceneContainsAVisiblePanel() {
        let image = DemoScenes.hero.render(scale: 1)
        // Some pixel must be far brighter than the darkest, i.e. the render
        // is not a flat fill.
        var minV = 1.0
        var maxV = 0.0
        for y in stride(from: 0, to: image.height, by: 3) {
            for x in stride(from: 0, to: image.width, by: 3) {
                let v = image.color(x: x, y: y).r
                minV = Swift.min(minV, v)
                maxV = Swift.max(maxV, v)
            }
        }
        XCTAssertGreaterThan(maxV - minV, 0.2)
    }

    func testSceneListIsStable() {
        // The CLI and the docs reference these names; renaming one is a
        // deliberate, breaking change.
        let expected = [
            "hero", "components", "merged-cluster", "magnifier", "button-states",
            "overlap", "panel-row", "spectrum-refraction", "starfield-specular",
            "bevel-modes", "bezel-width", "large-surface", "native-blur-lighting",
        ]
        XCTAssertEqual(DemoScenes.all.map(\.name), expected)
    }

    /// The `nativeBlur` lighting pass must show a lit rim, not a flat panel.
    ///
    /// This is the scene that guards the bug where a 1x1 backdrop collapsed the
    /// whole render to one pixel, so a regression shows up here as a nearly
    /// uniform image.
    func testNativeBlurLightingSceneHasAVisibleGradient() {
        let image = DemoScenes.nativeBlurLighting.render(scale: 1)
        var minV = 1.0
        var maxV = 0.0
        for y in stride(from: 0, to: image.height, by: 3) {
            for x in stride(from: 0, to: image.width, by: 3) {
                let v = image.color(x: x, y: y).r
                minV = Swift.min(minV, v)
                maxV = Swift.max(maxV, v)
            }
        }
        XCTAssertGreaterThan(maxV - minV, 0.2, "the additive lighting pass collapsed")
    }
}
