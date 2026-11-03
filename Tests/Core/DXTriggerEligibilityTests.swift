import XCTest
import DynamicStageXCore

final class DXTriggerEligibilityTests: XCTestCase {
    private func denial(enabled: Bool = true, locked: Bool = false, scene: Bool = true,
                        portrait: Bool = true, busy: Bool = false, dismissing: Bool = false,
                        overlay: Bool = false, phase: DXPhase = .idle,
                        identifier: String? = "com.apple.mobilesafari") -> DXTriggerBlock? {
        DXTriggerEligibility.denial(enabled: enabled, locked: locked, hasMainScene: scene,
            portrait: portrait, busy: busy, dismissing: dismissing, hasOverlay: overlay,
            phase: phase, frontmostIdentifier: identifier)
    }
    func testIdleApplicationAcceptedWithoutVersionOrModelGate() {
        XCTAssertNil(denial())
        XCTAssertNil(denial(identifier: "org.example.app-test_1"))
    }
    func testEveryBlockingGateHasAConcreteReason() {
        let cases: [(DXTriggerBlock?, DXTriggerBlock)] = [
            (denial(enabled: false), .disabled), (denial(locked: true), .locked),
            (denial(scene: false), .sceneUnavailable), (denial(portrait: false), .portraitRequired),
            (denial(busy: true), .busy), (denial(dismissing: true), .dismissing),
            (denial(overlay: true), .existingOverlay), (denial(identifier: nil), .missingFrontmost),
            (denial(identifier: ""), .missingFrontmost),
            (denial(identifier: "com.apple.springboard"), .homeScreen),
            (denial(identifier: "not a bundle"), .invalidFrontmost),
            (denial(phase: .preparing), .stateConflict)
        ]
        for (actual, expected) in cases { XCTAssertEqual(actual, expected) }
        XCTAssertEqual(Set(cases.map { $0.1 }), Set(DXTriggerBlock.allCases))
    }
    func testIdentifierBoundsAndCharactersRemainFailClosed() {
        for value in ["simple", "com.example.app\n", "com.example/app", "com.example.😀", String(repeating: "a", count: 255)+"."] {
            XCTAssertEqual(denial(identifier: value), .invalidFrontmost)
        }
    }
    func testBusyAndExternalStateDoNotFallThroughToAcquire() {
        for phase in DXPhase.allCases where phase != .idle {
            XCTAssertEqual(denial(phase: phase), .stateConflict)
        }
        XCTAssertEqual(denial(locked: true, busy: true, identifier: nil), .locked)
        XCTAssertEqual(denial(busy: true, identifier: nil), .busy)
        XCTAssertEqual(denial(dismissing: true, overlay: true), .dismissing)
    }
}
