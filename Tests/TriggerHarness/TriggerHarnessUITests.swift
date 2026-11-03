import XCTest

/// All input comes from public XCUIApplication/XCUICoordinate touch injection.
/// No fake UIPanGestureRecognizer state, accessibilityActivate(), or private XCTest APIs.
final class TriggerHarnessUITests: XCTestCase {
    private var app: XCUIApplication!
    private var strokes: [[String: Any]] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        strokes = []
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        if app != nil, app.state == .runningForeground {
            let keys = ["ready", "foreground", "nonKey", "layered", "triggers", "side", "enabled",
                        "sameSideWrites", "outsidePans", "buttonTaps"]
            var counters: [String: String] = [:]
            for key in keys {
                let element = app.staticTexts["Harness." + key]
                counters[key] = element.exists ? element.label : "MISSING"
            }
            let record: [String: Any] = ["test": name, "counters": counters, "strokes": strokes,
                "scope": "public XCUI touches in foreground UIKit app; not SpringBoard/remote HID"]
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .prettyPrinted]),
               let text = String(data: data, encoding: .utf8) {
                let attachment = XCTAttachment(string: text)
                attachment.name = "trigger-counters-and-coordinate-input.json"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "trigger-final-screen"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    private func value(_ key: String) -> String { app.staticTexts["Harness." + key].label }

    private func expect(_ key: String, _ value: String, file: StaticString = #filePath, line: UInt = #line) {
        let element = app.staticTexts["Harness." + key]
        let predicate = NSPredicate(format: "label == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "\(key): expected \(value), got \(element.exists ? element.label : "MISSING")",
                       file: file, line: line)
    }

    @discardableResult
    private func launch(left: Bool = false, disabled: Bool = false, repeatedSide: Bool = false) -> CGRect {
        app.launchArguments = (left ? ["--left"] : []) + (disabled ? ["--disabled"] : []) +
                              (repeatedSide ? ["--repeat-side"] : [])
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        expect("ready", "1")
        expect("foreground", "1")
        expect("nonKey", "1")
        expect("layered", "1")
        expect("triggers", "0")
        expect("side", left ? "left" : "right")
        expect("enabled", disabled ? "0" : "1")
        let handle = app.buttons["DX.edgeTrigger"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5), app.debugDescription)
        let rect = handle.frame
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
        XCTAssertTrue(app.frame.contains(rect))
        return rect
    }

    private func coordinate(_ point: CGPoint) -> XCUICoordinate {
        return app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }

    private func drag(from start: CGPoint, dx: CGFloat = 0, dy: CGFloat = -110, speed: CGFloat = 250) {
        let end = CGPoint(x: start.x + dx, y: start.y + dy)
        XCTAssertTrue(app.frame.insetBy(dx: 2, dy: 2).contains(end), "Endpoint must remain inside app")
        strokes.append(["kind": "coordinate-press-drag", "start": [start.x, start.y],
                        "end": [end.x, end.y], "velocityPointsPerSecond": speed,
                        "pressSeconds": 0.04, "endHoldSeconds": 0.12])
        coordinate(start).press(forDuration: 0.04, thenDragTo: coordinate(end),
                                withVelocity: XCUIGestureVelocity(rawValue: speed), thenHoldForDuration: 0.12)
        checkpoint()
    }

    private func checkpoint() {
        app.buttons["Harness.checkpoint"].tap()
        expect("ready", "1")
        expect("nonKey", "1")
    }

    private func upward(left: Bool = false, distance: CGFloat = 110, speed: CGFloat = 250,
                        repeatedSide: Bool = false) {
        let rect = launch(left: left, repeatedSide: repeatedSide)
        let start = CGPoint(x: rect.midX, y: rect.midY) // Visible indicator's actual centre.
        drag(from: start, dy: -distance, speed: speed)
        expect("triggers", "1")
        expect("outsidePans", "0") // The same touch must not leak to the key background window.
        if repeatedSide {
            XCTAssertGreaterThan(Int(value("sameSideWrites")) ?? 0, 5,
                                 "Main-run-loop same-side assignments must overlap this real drag")
        }
    }

    func testRightOrdinaryUp110() { upward() }
    func testLeftOrdinaryUp100() { upward(left: true, distance: 100) }
    func testRightShorterUp80() { upward(distance: 80) }
    func testLeftLongerUp140() { upward(left: true, distance: 140) }
    func testRightSlowUp110() { upward(speed: 65) }
    func testLeftSlowUp110() { upward(left: true, speed: 65) }
    func testRepeatedSameSideDoesNotCancelRealDrag() { upward(repeatedSide: true) }

    func testShortCoordinateTapDoesNotTrigger() {
        let rect = launch()
        let start = CGPoint(x: rect.midX, y: rect.midY)
        strokes.append(["kind": "coordinate-press-only", "point": [start.x, start.y], "seconds": 0.04])
        coordinate(start).press(forDuration: 0.04) // Not element.tap() / VoiceOver activation.
        checkpoint()
        expect("triggers", "0")
    }

    func testHorizontalRejected() {
        let rect = launch()
        drag(from: CGPoint(x: rect.midX, y: rect.midY), dx: -140, dy: 0)
        expect("triggers", "0")
    }

    func testMostlyHorizontalDiagonalRejected() {
        let rect = launch()
        drag(from: CGPoint(x: rect.midX, y: rect.midY), dx: -140, dy: -70)
        expect("triggers", "0")
    }

    func testDownwardRejected() {
        let rect = launch()
        drag(from: CGPoint(x: rect.midX, y: rect.minY + 6), dy: 44)
        expect("triggers", "0")
    }

    func testOutsideRegionDoesNotSwallowBackgroundInput() {
        let rect = launch()
        app.buttons["Harness.backgroundButton"].tap()
        expect("buttonTaps", "1")
        drag(from: CGPoint(x: rect.minX - 90, y: rect.midY))
        expect("triggers", "0")
        expect("outsidePans", "1")
        app.buttons["Harness.backgroundButton"].tap()
        expect("buttonTaps", "2")
    }

    func testDisabledRegionPassesTouchToBackgroundWithoutTrigger() {
        let rect = launch(disabled: true)
        drag(from: CGPoint(x: rect.midX, y: rect.midY))
        expect("triggers", "0")
        expect("outsidePans", "1")
    }

    func testVisibleIndicatorHasForgivingTouchStrip() {
        let rect = launch(left: true)
        // Assert the alpha3 target contract, not a duplicate policy implementation.
        XCTAssertGreaterThanOrEqual(rect.width, 44)
        XCTAssertGreaterThanOrEqual(rect.height, 56)
        drag(from: CGPoint(x: rect.midX + 23, y: rect.midY))
        expect("triggers", "1")
    }
}
