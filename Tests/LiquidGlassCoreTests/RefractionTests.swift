import XCTest
@testable import LiquidGlassCore

final class RefractionTests: XCTestCase {

    private let half = LGPoint(x: 100, y: 60)
    private let radius = 30.0
    private let zRadius = 40.0

    private func offset(
        at p: LGPoint,
        refraction: Double = 0.69,
        mode: GlassBevelMode = .biconvex
    ) -> LGPoint {
        let sample = GlassMath.surfaceSample(
            localPx: p, halfExtent: half, radius: radius, zRadius: zRadius
        )
        return GlassMath.refractionOffset(
            localPx: p,
            halfExtent: half,
            zRadius: zRadius,
            refraction: refraction,
            bevelMode: mode,
            height: sample.height,
            gradient: sample.gradient,
            distanceInside: sample.distanceInside
        )
    }

    func testRefractionIsZeroAtTheCentre() {
        // The bevel plateau is flat, and the centre-directed pull is zero, so
        // the middle of a panel samples straight through.
        let o = offset(at: .zero)
        XCTAssertEqual(o.x, 0, accuracy: 1e-9)
        XCTAssertEqual(o.y, 0, accuracy: 1e-9)
    }

    func testRefractionIsZeroOutsideThePanel() {
        let o = offset(at: LGPoint(x: 200, y: 0))
        XCTAssertEqual(o.x, 0, accuracy: 1e-9)
        XCTAssertEqual(o.y, 0, accuracy: 1e-9)
    }

    func testBiconvexRefractionIsLargestAtTheEdge() {
        let nearEdge = offset(at: LGPoint(x: 96, y: 0))
        let midBevel = offset(at: LGPoint(x: 75, y: 0))
        let centre = offset(at: .zero)
        XCTAssertGreaterThan(abs(nearEdge.x), abs(midBevel.x))
        XCTAssertGreaterThan(abs(midBevel.x), abs(centre.x))
    }

    func testBiconvexRefractionPullsSampleTowardTheCentre() {
        // Both the gradient term and the centre-directed pull point inward at
        // the right edge, so the backdrop is sampled from nearer the panel
        // centre. This is what compresses the backdrop into the rim.
        let o = offset(at: LGPoint(x: 96, y: 0))
        XCTAssertLessThan(o.x, 0)
    }

    func testBiconvexRefractionIsSymmetricAcrossTheCentre() {
        let right = offset(at: LGPoint(x: 80, y: 0))
        let left = offset(at: LGPoint(x: -80, y: 0))
        XCTAssertEqual(left.x, -right.x, accuracy: 1e-9)
    }

    func testBiconvexRefractionScalesLinearlyWithStrength() {
        let p = LGPoint(x: 90, y: 20)
        let a = offset(at: p, refraction: 0.5)
        let b = offset(at: p, refraction: 1.0)
        XCTAssertEqual(b.x, a.x * 2, accuracy: 1e-9)
        XCTAssertEqual(b.y, a.y * 2, accuracy: 1e-9)
    }

    func testDomeModeContractsTowardCentre() {
        // Dome refraction scales the local position by a negative factor, so
        // the sampled point moves toward the centre of the panel.
        let p = LGPoint(x: 60, y: 0)
        let o = offset(at: p, mode: .dome)
        XCTAssertLessThan(o.x, 0)
        XCTAssertEqual(o.y, 0, accuracy: 1e-12)
    }

    func testDomeModeIsZeroAtTheCentreAndOutside() {
        XCTAssertEqual(offset(at: .zero, mode: .dome).x, 0, accuracy: 1e-12)
        XCTAssertEqual(offset(at: LGPoint(x: 150, y: 0), mode: .dome).x, 0, accuracy: 1e-12)
    }

    func testDomeMagnifierMovesSamplesInward() {
        // A point at 3/4 of the way out should sample from nearer the centre,
        // which is what makes the dome read as a magnifier.
        let p = LGPoint(x: 70, y: 0)
        let sample = GlassMath.surfaceSample(localPx: p, halfExtent: half, radius: radius, zRadius: zRadius)
        let o = GlassMath.refractionOffset(
            localPx: p, halfExtent: half, zRadius: zRadius, refraction: 1.2,
            bevelMode: .dome, height: sample.height, gradient: sample.gradient,
            distanceInside: sample.distanceInside
        )
        let sampledPoint = LGPoint(x: p.x + o.x, y: p.y + o.y)
        XCTAssertLessThan(abs(sampledPoint.x), abs(p.x))
    }

    func testZeroRefractionProducesNoOffset() {
        XCTAssertEqual(offset(at: LGPoint(x: 96, y: 0), refraction: 0).x, 0, accuracy: 1e-12)
        XCTAssertEqual(offset(at: LGPoint(x: 96, y: 0), refraction: 0, mode: .dome).x, 0, accuracy: 1e-12)
    }
}
