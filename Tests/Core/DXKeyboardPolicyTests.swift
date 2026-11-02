import XCTest
import DynamicStageXCore

final class DXKeyboardPolicyTests: XCTestCase {
    private let bounds = DXRect(x: 0, y: 0, width: 390, height: 844)
    private let safe = DXInsets(top: 47, bottom: 34)

    func testDockedKeyboardUsesSafeTopAndActualKeyboardTop() throws {
        let shifted = DXRect(x: 10, y: 20, width: 390, height: 844)
        let insets = DXInsets(top: 47, left: 3, bottom: 34, right: 4)
        let keyboard = DXRect(x: 10, y: 600, width: 390, height: 264)
        XCTAssertEqual(DXKeyboardPolicy.occlusion(bounds: shifted, safeArea: insets, keyboard: keyboard),
                       .docked(DXRect(x: 13, y: 600, width: 383, height: 230)))
        let frame = try XCTUnwrap(DXKeyboardPolicy.focusedFrame(
            bounds: shifted, safeArea: insets, keyboard: keyboard, minimumHeight: 200
        ))
        XCTAssertEqual(frame, DXRect(x: 13, y: 67, width: 383, height: 533))
        XCTAssertTrue(DXKeyboardPolicy.isDocked(keyboard: keyboard, bounds: shifted))
    }

    func testFloatingAndNarrowBottomKeyboardDoNotPromote() {
        for keyboard in [
            DXRect(x: 100, y: 400, width: 200, height: 180),
            DXRect(x: 100, y: 700, width: 200, height: 144),
            DXRect(x: 0, y: 300, width: 390, height: 200)
        ] {
            guard case .some(.floating(_)) = DXKeyboardPolicy.occlusion(
                bounds: bounds, safeArea: safe, keyboard: keyboard
            ) else { return XCTFail("floating keyboard was not classified as floating") }
            XCTAssertFalse(DXKeyboardPolicy.isDocked(keyboard: keyboard, bounds: bounds))
            XCTAssertNil(DXKeyboardPolicy.focusedFrame(
                bounds: bounds, safeArea: safe, keyboard: keyboard, minimumHeight: 100
            ))
        }
    }

    func testHardwareHiddenOffscreenAndSafeAreaOnlyDoNotPromote() {
        for keyboard in [
            .zero,
            DXRect(x: 0, y: 844, width: 390, height: 0),
            DXRect(x: 0, y: 844, width: 390, height: 300),
            DXRect(x: 500, y: 400, width: 200, height: 400),
            DXRect(x: 0, y: 810, width: 390, height: 34)
        ] {
            XCTAssertEqual(DXKeyboardPolicy.occlusion(bounds: bounds, safeArea: safe, keyboard: keyboard),
                           .some(.none))
            XCTAssertNil(DXKeyboardPolicy.focusedFrame(
                bounds: bounds, safeArea: safe, keyboard: keyboard, minimumHeight: 100
            ))
        }
        XCTAssertFalse(DXKeyboardPolicy.isDocked(keyboard: .zero, bounds: bounds))
    }

    func testAccessoryBarAndChangingKeyboardHeightUseSamePolicy() throws {
        for top in [500.0, 600, 780, 800] {
            let keyboard = DXRect(x: 0, y: top, width: 390, height: 844 - top)
            let frame = try XCTUnwrap(DXKeyboardPolicy.focusedFrame(
                bounds: bounds, safeArea: safe, keyboard: keyboard, minimumHeight: 200
            ))
            XCTAssertEqual(frame.maxY, top)
            XCTAssertEqual(frame.minY, 47)
            XCTAssertEqual(frame.height, top - 47)
        }
    }

    func testKeyboardClippingToleranceAndMinimumHeight() {
        XCTAssertTrue(DXKeyboardPolicy.isDocked(
            keyboard: DXRect(x: -50, y: 600, width: 500, height: 400), bounds: bounds
        ))
        XCTAssertTrue(DXKeyboardPolicy.isDocked(
            keyboard: DXRect(x: 0.5, y: 600, width: 389, height: 243.5), bounds: bounds
        ))
        XCTAssertFalse(DXKeyboardPolicy.isDocked(
            keyboard: DXRect(x: 0, y: 600, width: 390, height: 242), bounds: bounds
        ))
        let keyboard = DXRect(x: 0, y: 100, width: 390, height: 744)
        XCTAssertNil(DXKeyboardPolicy.focusedFrame(
            bounds: bounds, safeArea: safe, keyboard: keyboard, minimumHeight: 54
        ))
        XCTAssertNotNil(DXKeyboardPolicy.focusedFrame(
            bounds: bounds, safeArea: safe, keyboard: keyboard, minimumHeight: 53
        ))
        XCTAssertNil(DXKeyboardPolicy.focusedFrame(
            bounds: bounds, safeArea: safe, keyboard: bounds, minimumHeight: 1
        ))
    }

    func testInvalidKeyboardInputsFailExplicitly() {
        for keyboard in [
            DXRect(x: 0, y: .nan, width: 390, height: 300),
            DXRect(x: 0, y: 600, width: 390, height: -1)
        ] {
            XCTAssertNil(DXKeyboardPolicy.occlusion(bounds: bounds, safeArea: safe, keyboard: keyboard))
        }
        XCTAssertNil(DXKeyboardPolicy.occlusion(bounds: .zero, safeArea: safe, keyboard: bounds))
        XCTAssertNil(DXKeyboardPolicy.occlusion(bounds: bounds, safeArea: DXInsets(top: -1), keyboard: bounds))
        XCTAssertNil(DXKeyboardPolicy.occlusion(bounds: bounds, safeArea: safe, keyboard: bounds, edgeTolerance: -.infinity))
        let keyboard = DXRect(x: 0, y: 600, width: 390, height: 244)
        for minimum in [0.0, -1, .nan, .infinity] {
            XCTAssertNil(DXKeyboardPolicy.focusedFrame(
                bounds: bounds, safeArea: safe, keyboard: keyboard, minimumHeight: minimum
            ))
        }
    }

    func testFloatingSubtractionPreservesSpaceBelowAndOnBothSides() throws {
        let usable = try XCTUnwrap(bounds.inset(by: safe))
        let keyboard = DXRect(x: 100, y: 400, width: 200, height: 180)
        let regions = DXKeyboardPolicy.unobscuredRegions(in: usable, avoiding: keyboard)
        XCTAssertEqual(regions.count, 4)
        XCTAssertEqual(regions[1], DXRect(x: 0, y: 580, width: 390, height: 230))
        var area = 0.0
        for (index, region) in regions.enumerated() {
            XCTAssertTrue(usable.contains(region))
            XCTAssertNil(region.intersection(keyboard))
            area += region.width * region.height
            for other in regions.dropFirst(index + 1) { XCTAssertNil(region.intersection(other)) }
        }
        XCTAssertEqual(area, usable.width * usable.height - keyboard.width * keyboard.height, accuracy: 1e-9)
        XCTAssertEqual(DXKeyboardPolicy.unobscuredRegions(in: usable, avoiding: .zero), [usable])
        XCTAssertEqual(DXKeyboardPolicy.unobscuredRegions(in: usable, avoiding: bounds), [])
        XCTAssertEqual(DXKeyboardPolicy.unobscuredRegions(
            in: usable, avoiding: DXRect(x: 0, y: 0, width: -1, height: 1)
        ), [])
    }
}
