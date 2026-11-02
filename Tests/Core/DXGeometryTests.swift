import XCTest
import DynamicStageXCore

final class DXGeometryTests: XCTestCase {
    func testRectValidityAndEmptySemantics() {
        XCTAssertTrue(DXRect.zero.isValid)
        XCTAssertFalse(DXRect.zero.hasArea)
        XCTAssertFalse(DXRect.zero.contains(x: 0, y: 0))
        for bad in [
            DXRect(x: .nan, y: 0, width: 1, height: 1),
            DXRect(x: 0, y: .infinity, width: 1, height: 1),
            DXRect(x: 0, y: 0, width: -1, height: 1),
            DXRect(x: 0, y: 0, width: 1, height: -.infinity),
            DXRect(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 1)
        ] { XCTAssertFalse(bad.isValid) }
        let unrepresentable = DXRect(x: 1, y: 0, width: .leastNonzeroMagnitude, height: 1)
        XCTAssertTrue(unrepresentable.isValid)
        XCTAssertFalse(unrepresentable.hasArea)
    }

    func testIntersectionClipsBothAxesWithNegativeOrigins() {
        let a = DXRect(x: -20, y: -10, width: 40, height: 30)
        let b = DXRect(x: 0, y: 5, width: 50, height: 20)
        let expected = DXRect(x: 0, y: 5, width: 20, height: 15)
        XCTAssertEqual(a.intersection(b), expected)
        XCTAssertEqual(b.intersection(a), expected)
        XCTAssertTrue(a.contains(expected))
        XCTAssertNil(a.intersection(DXRect(x: 20, y: 0, width: 1, height: 1)))
        XCTAssertNil(a.intersection(.zero))
        XCTAssertFalse(a.contains(x: .nan, y: 0))
        XCTAssertTrue(a.contains(x: -20, y: -10))
    }

    func testInsetsRejectInvalidAndEmptyUsableArea() {
        let bounds = DXRect(x: 10, y: 20, width: 100, height: 80)
        XCTAssertEqual(bounds.inset(by: DXInsets(top: 3, left: 4, bottom: 5, right: 6)),
                       DXRect(x: 14, y: 23, width: 90, height: 72))
        XCTAssertNil(bounds.inset(by: DXInsets(left: -1)))
        XCTAssertNil(bounds.inset(by: DXInsets(bottom: .nan)))
        XCTAssertNil(bounds.inset(by: DXInsets(left: 50, right: 50)))
        XCTAssertNil(bounds.inset(by: DXInsets(top: 81)))
        XCTAssertNil(bounds.inset(by: DXInsets(left: .greatestFiniteMagnitude, right: .greatestFiniteMagnitude)))
    }

    func testSafeAreaOriginMarginsGapAndRatio() throws {
        let layout = try XCTUnwrap(DXLayoutPolicy.split(
            bounds: DXRect(x: 10, y: 20, width: 390, height: 844),
            safeArea: DXInsets(top: 47, left: 3, bottom: 34, right: 4),
            ratio: 0.5, gap: 12, margin: 8, radius: 28
        ))
        XCTAssertEqual(layout.top, DXRect(x: 21, y: 75, width: 367, height: 367.5))
        XCTAssertEqual(layout.bottom, DXRect(x: 21, y: 454.5, width: 367, height: 367.5))
        XCTAssertEqual(layout.topRadius, 28)
        XCTAssertEqual(layout.bottomRadius, 28)
    }

    func testRatioAndEachRadiusAreIndependent() throws {
        let layout = try XCTUnwrap(DXLayoutPolicy.split(
            bounds: DXRect(x: 0, y: 0, width: 200, height: 110), safeArea: .zero,
            ratio: 0.2, gap: 10, margin: 0, radius: 1000
        ))
        XCTAssertEqual(layout.top.height, 20)
        XCTAssertEqual(layout.bottom.height, 80)
        XCTAssertEqual(layout.topRadius, 10)
        XCTAssertEqual(layout.bottomRadius, 40)
    }

    func testLayoutRejectsInvalidParametersInsteadOfClamping() {
        let bounds = DXRect(x: 0, y: 0, width: 100, height: 200)
        for ratio in [0.0, 1, -0.1, 1.1, .nan, .infinity] {
            XCTAssertNil(DXLayoutPolicy.split(bounds: bounds, safeArea: .zero,
                                            ratio: ratio, gap: 0, margin: 0, radius: 0))
        }
        for value in [-1.0, .nan, .infinity] {
            XCTAssertNil(DXLayoutPolicy.split(bounds: bounds, safeArea: .zero,
                                            ratio: 0.5, gap: value, margin: 0, radius: 0))
            XCTAssertNil(DXLayoutPolicy.split(bounds: bounds, safeArea: .zero,
                                            ratio: 0.5, gap: 0, margin: value, radius: 0))
            XCTAssertNil(DXLayoutPolicy.split(bounds: bounds, safeArea: .zero,
                                            ratio: 0.5, gap: 0, margin: 0, radius: value))
        }
        XCTAssertNil(DXLayoutPolicy.split(bounds: bounds, safeArea: .zero,
                                        ratio: 0.5, gap: 200, margin: 0, radius: 0))
        XCTAssertNil(DXLayoutPolicy.split(bounds: bounds, safeArea: DXInsets(top: 200),
                                        ratio: 0.5, gap: 0, margin: 0, radius: 0))
        XCTAssertNil(DXLayoutPolicy.split(bounds: bounds, safeArea: .zero,
                                        ratio: 0.5, gap: 0, margin: 50, radius: 0))
        XCTAssertNil(DXLayoutPolicy.split(bounds: .zero, safeArea: .zero,
                                        ratio: 0.5, gap: 0, margin: 0, radius: 0))
        XCTAssertNil(DXLayoutPolicy.split(
            bounds: DXRect(x: 0, y: 1e16, width: 100, height: 1000), safeArea: .zero,
            ratio: 0.5, gap: 0.001, margin: 0, radius: 0
        ))
    }

    func testLayoutInvariantsAcrossPointSizesAndOrientations() throws {
        let sizes: [(Double, Double)] = [(320, 568), (375, 667), (390, 844), (430, 932), (844, 390)]
        let insets: [DXInsets] = [.zero, DXInsets(top: 20), DXInsets(top: 59, left: 4, bottom: 34, right: 3)]
        for (width, height) in sizes {
            for safeArea in insets {
                for ratio in [0.1, 0.5, 0.83] {
                    let bounds = DXRect(x: -7, y: 11, width: width, height: height)
                    let usable = try XCTUnwrap(bounds.inset(by: safeArea)?.inset(
                        by: DXInsets(top: 6, left: 6, bottom: 6, right: 6)
                    ))
                    let layout = try XCTUnwrap(DXLayoutPolicy.split(
                        bounds: bounds, safeArea: safeArea, ratio: ratio, gap: 8, margin: 6, radius: 28
                    ))
                    XCTAssertTrue(usable.contains(layout.top))
                    XCTAssertTrue(usable.contains(layout.bottom))
                    XCTAssertNil(layout.top.intersection(layout.bottom))
                    XCTAssertEqual(layout.bottom.minY - layout.top.maxY, 8, accuracy: 1e-9)
                    XCTAssertEqual(layout.bottom.maxY, usable.maxY, accuracy: 1e-9)
                    XCTAssertEqual(layout.top.height + layout.bottom.height + 8, usable.height, accuracy: 1e-9)
                    XCTAssertEqual(layout.top.height / (layout.top.height + layout.bottom.height), ratio, accuracy: 1e-12)
                }
            }
        }
    }

    func testCircularHitTestingAllCornersAndBounds() {
        let bounds = DXRect(x: 10, y: 20, width: 100, height: 100)
        for (x, y) in [(10.0, 20.0), (110, 20), (10, 120), (110, 120), (15, 25)] {
            XCTAssertFalse(DXRoundedHitTest.contains(x: x, y: y, in: bounds, radius: 20))
        }
        for (x, y) in [(30.0, 20.0), (10, 50), (60, 70), (20, 30), (100, 110)] {
            XCTAssertTrue(DXRoundedHitTest.contains(x: x, y: y, in: bounds, radius: 20))
        }
        XCTAssertFalse(DXRoundedHitTest.contains(x: 9, y: 70, in: bounds, radius: 0))
        XCTAssertTrue(DXRoundedHitTest.contains(x: 10, y: 20, in: bounds, radius: 0))
        XCTAssertFalse(DXRoundedHitTest.contains(x: .nan, y: 70, in: bounds, radius: 20))
        XCTAssertFalse(DXRoundedHitTest.contains(x: 60, y: 70, in: bounds, radius: -1))
        XCTAssertFalse(DXRoundedHitTest.contains(x: 60, y: 70, in: bounds, radius: .infinity))
        XCTAssertTrue(DXRoundedHitTest.contains(x: 60, y: 20, in: bounds, radius: 1000))
        XCTAssertFalse(DXRoundedHitTest.contains(x: 10, y: 20, in: bounds, radius: 1000))
    }
}
