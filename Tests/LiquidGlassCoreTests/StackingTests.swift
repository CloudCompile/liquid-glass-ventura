import XCTest
@testable import LiquidGlassCore

final class StackingTests: XCTestCase {

    func testNonContextElementsPaintFirstInDOMOrder() {
        let traits = [
            StackingTraits(positionIsStatic: true, domIndex: 0),
            StackingTraits(positionIsStatic: true, domIndex: 1),
        ]
        XCTAssertEqual(paintingOrder(traits), [0, 1])
    }

    func testContextElementsPaintAfterPlainOnesRegardlessOfZIndex() {
        // A plain element with z-index 99 still paints below a context
        // element, because the plain element never leaves the in-flow layer.
        let traits = [
            StackingTraits(positionIsStatic: false, zIndex: 99, domIndex: 0),
            StackingTraits(positionIsStatic: true, zIndex: nil, domIndex: 1),
        ]
        XCTAssertEqual(paintingOrder(traits), [1, 0])
    }

    func testContextElementsSortByZIndexThenDOMOrder() {
        let traits = [
            StackingTraits(positionIsStatic: false, zIndex: 2, domIndex: 0),
            StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 1),
            StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: 2),
        ]
        XCTAssertEqual(paintingOrder(traits), [1, 2, 0])
    }

    func testOpacityCreatesAStackingContext() {
        let traits = [
            StackingTraits(positionIsStatic: true, hasOpacity: true, zIndex: 5, domIndex: 0),
            StackingTraits(positionIsStatic: true, domIndex: 1),
        ]
        XCTAssertEqual(paintingOrder(traits), [1, 0])
    }

    func testNegativeZIndexContextPaintsAbovePlainContent() {
        // This is the counter-intuitive part of the spec that the reference
        // library re-implements: z-index -1 still beats a plain in-flow
        // element.
        let traits = [
            StackingTraits(positionIsStatic: true, domIndex: 0),
            StackingTraits(positionIsStatic: false, zIndex: -1, domIndex: 1),
        ]
        XCTAssertEqual(paintingOrder(traits), [0, 1])
    }

    func testIsolatingPropertiesAndContainmentCreateContexts() {
        XCTAssertTrue(StackingTraits(hasIsolatingProperty: true).formsStackingContext)
        XCTAssertTrue(StackingTraits(hasContainment: true).formsStackingContext)
        XCTAssertTrue(StackingTraits(isFlexOrGridItemWithZIndex: true).formsStackingContext)
        XCTAssertFalse(StackingTraits().formsStackingContext)
    }

    func testOrderingIsStableForEqualTraits() {
        let traits = (0..<6).map { StackingTraits(positionIsStatic: false, zIndex: 1, domIndex: $0) }
        XCTAssertEqual(paintingOrder(traits), [0, 1, 2, 3, 4, 5])
    }
}
