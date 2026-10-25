import XCTest
@testable import LiquidGlassCore

/// The container's merging rule: which surfaces share one panel.
final class GlassClustererTests: XCTestCase {

    private func rect(_ x: Double, _ y: Double, _ w: Double = 100, _ h: Double = 50) -> LGRect {
        LGRect(x: x, y: y, width: w, height: h)
    }

    func testEmptyInputGivesNoClusters() {
        XCTAssertTrue(GlassClusterer.clusters(frames: [], spacing: 20).isEmpty)
    }

    func testDistantSurfacesStaySeparate() {
        let clusters = GlassClusterer.clusters(
            frames: [rect(0, 0), rect(400, 0)],
            spacing: 20
        )
        XCTAssertEqual(clusters, [[0], [1]])
    }

    func testOverlappingSurfacesMerge() {
        let clusters = GlassClusterer.clusters(
            frames: [rect(0, 0), rect(50, 0)],
            spacing: 0
        )
        XCTAssertEqual(clusters, [[0, 1]])
    }

    func testGapSmallerThanSpacingMerges() {
        // The frames are 100 wide, so index 1 starts 100 + gap away.
        let clusters = GlassClusterer.clusters(
            frames: [rect(0, 0), rect(100 + 20, 0)],
            spacing: 24
        )
        XCTAssertEqual(clusters, [[0, 1]])
    }

    func testGapEqualToSpacingIsTheBoundaryAndDoesNotMerge() {
        let clusters = GlassClusterer.clusters(
            frames: [rect(0, 0), rect(100 + 24, 0)],
            spacing: 24
        )
        XCTAssertEqual(clusters, [[0], [1]])
    }

    func testGapLargerThanSpacingStaysSeparate() {
        let clusters = GlassClusterer.clusters(
            frames: [rect(0, 0), rect(100 + 30, 0)],
            spacing: 24
        )
        XCTAssertEqual(clusters, [[0], [1]])
    }

    func testMergingIsTransitive() {
        // 0 touches 1, 1 touches 2, but 0 does not touch 2.
        let clusters = GlassClusterer.clusters(
            frames: [rect(0, 0), rect(115, 0), rect(230, 0)],
            spacing: 24
        )
        XCTAssertEqual(clusters, [[0, 1, 2]])
    }

    func testEveryIndexAppearsExactlyOnce() {
        let frames = [rect(0, 0), rect(10, 0), rect(500, 0), rect(505, 0), rect(900, 0)]
        let clusters = GlassClusterer.clusters(frames: frames, spacing: 20)
        let flattened = clusters.flatMap { $0 }.sorted()
        XCTAssertEqual(flattened, Array(0..<frames.count))
    }

    func testDiagonalNeighboursMerge() {
        let clusters = GlassClusterer.clusters(
            frames: [rect(0, 0), rect(120, 60)],
            spacing: 24
        )
        XCTAssertEqual(clusters, [[0, 1]])
    }

    func testZeroSpacingRequiresRealOverlap() {
        let clusters = GlassClusterer.clusters(
            frames: [rect(0, 0), rect(100, 0)],
            spacing: 0
        )
        XCTAssertEqual(clusters, [[0], [1]])
    }

    func testBoundsCoverTheWholeGroup() {
        let frames = [rect(10, 20, 100, 50), rect(200, 5, 40, 30)]
        let box = GlassClusterer.bounds(of: frames, indices: [0, 1])
        XCTAssertEqual(box.x, 10)
        XCTAssertEqual(box.y, 5)
        XCTAssertEqual(box.width, 230)
        XCTAssertEqual(box.height, 65)
    }

    func testBoundsOfSingleFrameIsThatFrame() {
        let frames = [rect(7, 9, 30, 40)]
        let box = GlassClusterer.bounds(of: frames, indices: [0])
        XCTAssertEqual(box, frames[0])
    }
}
