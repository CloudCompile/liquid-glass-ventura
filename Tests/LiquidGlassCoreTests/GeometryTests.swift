import XCTest
@testable import LiquidGlassCore

final class GeometryTests: XCTestCase {

    func testRoundedRectSDFIsNegativeInsideAndPositiveOutside() {
        let b = LGPoint(x: 50, y: 30)
        // Dead centre.
        XCTAssertLessThan(GlassMath.roundedRectSDF(.zero, halfExtent: b, radius: 10), 0)
        // Just inside the right edge.
        XCTAssertLessThan(GlassMath.roundedRectSDF(LGPoint(x: 49, y: 0), halfExtent: b, radius: 10), 0)
        // Just outside the right edge.
        XCTAssertGreaterThan(GlassMath.roundedRectSDF(LGPoint(x: 51, y: 0), halfExtent: b, radius: 10), 0)
    }

    func testRoundedRectSDFMatchesExactDistanceOnStraightEdge() {
        let b = LGPoint(x: 50, y: 30)
        // On the straight part of the right edge the distance is exact.
        let d = GlassMath.roundedRectSDF(LGPoint(x: 60, y: 0), halfExtent: b, radius: 10)
        XCTAssertEqual(d, 10, accuracy: 1e-9)
    }

    func testRoundedRectSDFDistanceAtCornerCentre() {
        let b = LGPoint(x: 50, y: 30)
        let r = 10.0
        // 45 degrees out from the top-right corner circle.
        let k = r / 2.0.squareRoot()
        let p = LGPoint(x: b.x - r + k, y: b.y - r + k)
        XCTAssertEqual(GlassMath.roundedRectSDF(p, halfExtent: b, radius: r), 0, accuracy: 1e-9)
    }

    func testBevelHeightIsZeroAtEdgeAndPeaksAtZRadius() {
        XCTAssertEqual(GlassMath.bevelHeight(distanceInside: 0, zRadius: 40), 0, accuracy: 1e-12)
        XCTAssertEqual(GlassMath.bevelHeight(distanceInside: -5, zRadius: 40), 0, accuracy: 1e-12)
        XCTAssertEqual(GlassMath.bevelHeight(distanceInside: 40, zRadius: 40), 40, accuracy: 1e-12)
        XCTAssertEqual(GlassMath.bevelHeight(distanceInside: 900, zRadius: 40), 40, accuracy: 1e-12)
    }

    func testBevelHeightFollowsHalfCircle() {
        let zR = 40.0
        // Mid-bevel: sqrt(d * (2zR - d)).
        let d = 10.0
        XCTAssertEqual(
            GlassMath.bevelHeight(distanceInside: d, zRadius: zR),
            (d * (2 * zR - d)).squareRoot(),
            accuracy: 1e-12
        )
    }

    func testBevelIsMonotonicIncreasing() {
        var previous = -1.0
        for d in stride(from: 0.0, through: 40.0, by: 0.5) {
            let h = GlassMath.bevelHeight(distanceInside: d, zRadius: 40)
            XCTAssertGreaterThanOrEqual(h, previous)
            previous = h
        }
    }

    func testSurfaceNormalIsUnitLength() {
        let sample = GlassMath.surfaceSample(
            localPx: LGPoint(x: 30, y: 18),
            halfExtent: LGPoint(x: 50, y: 30),
            radius: 12,
            zRadius: 20
        )
        let n = sample.normal
        let len = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
        XCTAssertEqual(len, 1, accuracy: 1e-12)
    }

    func testSurfaceNormalIsFlatAtPanelCentre() {
        let sample = GlassMath.surfaceSample(
            localPx: .zero,
            halfExtent: LGPoint(x: 50, y: 30),
            radius: 12,
            zRadius: 20
        )
        // Centre of the bevel plateau: gradient zero, normal straight up.
        XCTAssertEqual(sample.gradient.x, 0, accuracy: 1e-9)
        XCTAssertEqual(sample.gradient.y, 0, accuracy: 1e-9)
        XCTAssertEqual(sample.normal.z, 1, accuracy: 1e-9)
    }

    func testSurfaceRisesTowardTheInteriorInsideTheBevel() {
        // Within the bevel (less than zRadius inside the edge) the height
        // still climbs toward the centre, so the gradient points inward and
        // the normal tilts outward.
        let sample = GlassMath.surfaceSample(
            localPx: LGPoint(x: 46, y: 0),
            halfExtent: LGPoint(x: 50, y: 30),
            radius: 12,
            zRadius: 20
        )
        XCTAssertLessThan(sample.gradient.x, 0, "height must still be rising toward the interior")
        XCTAssertGreaterThan(sample.normal.x, 0, "the normal leans away from the rising surface")
    }

    func testSurfaceGradientFlipsBeyondTheBevel() {
        // Past zRadius inside, the height has plateaued, so the gradient falls
        // back to zero and the surface is flat.
        let sample = GlassMath.surfaceSample(
            localPx: LGPoint(x: 20, y: 0),
            halfExtent: LGPoint(x: 50, y: 30),
            radius: 12,
            zRadius: 20
        )
        XCTAssertEqual(sample.gradient.x, 0, accuracy: 1e-12)
        XCTAssertEqual(sample.normal.z, 1, accuracy: 1e-12)
    }

    func testSurfaceSampleReportsInsideDistance() {
        let sample = GlassMath.surfaceSample(
            localPx: LGPoint(x: 45, y: 0),
            halfExtent: LGPoint(x: 50, y: 30),
            radius: 12,
            zRadius: 20
        )
        XCTAssertEqual(sample.distanceInside, 5, accuracy: 1e-9)
    }

    func testSmoothstepMatchesGLSL() {
        XCTAssertEqual(GlassMath.smoothstep(0, 1, -1), 0)
        XCTAssertEqual(GlassMath.smoothstep(0, 1, 2), 1)
        XCTAssertEqual(GlassMath.smoothstep(0, 1, 0.5), 0.5, accuracy: 1e-12)
        // 3t² - 2t³ at t = 0.25.
        XCTAssertEqual(GlassMath.smoothstep(0, 1, 0.25), 0.15625, accuracy: 1e-12)
    }

    func testSmoothstepHandlesDegenerateEdges() {
        XCTAssertEqual(GlassMath.smoothstep(1, 1, 0.5), 0)
        XCTAssertEqual(GlassMath.smoothstep(1, 1, 1.5), 1)
    }

    func testHashIsDeterministicAndInUnitRange() {
        let p = LGPoint(x: 3.5, y: -2.25)
        let a = GlassMath.hash(p)
        let b = GlassMath.hash(p)
        XCTAssertEqual(a, b)
        for x in stride(from: -5.0, through: 5.0, by: 0.37) {
            let v = GlassMath.hash(LGPoint(x: x, y: x * 1.7))
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThan(v, 1)
        }
    }
}
