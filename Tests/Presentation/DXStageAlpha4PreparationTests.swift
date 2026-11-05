import XCTest
import UIKit

// Add production stage/chrome/pane/picker/overlay/geometry + Core/DXGeometry.swift
// and DXStageAlpha4Checks.swift to an iOS XCTest target. Use the real bridge record
// OR Alpha4PickerRecordFixture.swift (not both). No production private bridge calls.
final class DXStageAlpha4PreparationTests: XCTestCase {
    func testProductionPreparationAndNonOverlappingChrome() {
        let run = {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let result = DXStageAlpha4Checks.run(in: window)
            window.isHidden = true
            XCTAssertGreaterThan(result.checks, 50)
            XCTAssertTrue(result.failures.isEmpty, result.failures.joined(separator: "\n"))
        }
        if Thread.isMainThread { run() } else { DispatchQueue.main.sync(execute: run) }
    }
}
