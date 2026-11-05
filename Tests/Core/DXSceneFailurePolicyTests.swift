import Foundation
import XCTest
import DynamicStageXCore

final class DXSceneFailurePolicyTests: XCTestCase {
    private func fault(_ message: String, extra: [String: Any] = [:]) -> NSError {
        var info = extra
        info[NSLocalizedDescriptionKey] = message
        return NSError(domain: "fixture.scene", code: 8, userInfo: info)
    }
    func testPrimaryCauseAlwaysPrecedesRecoveryError() throws {
        let text = try XCTUnwrap(DXFailurePolicy.description(primary: fault("original timeout"), cleanup: fault("cleanup exception")))
        let original = try XCTUnwrap(text.range(of: "original timeout"))
        let cleanup = try XCTUnwrap(text.range(of: "cleanup exception"))
        XCTAssertLessThan(original.lowerBound, cleanup.lowerBound)
    }
    func testBridgeAttachedRecoveryIsNotDiscardedWhenBarrierAlreadyFinished() throws {
        let cleanup = fault("detach error")
        let primary = fault("settings timeout", extra: [NSUnderlyingErrorKey: cleanup])
        let text = try XCTUnwrap(DXFailurePolicy.description(primary: primary, cleanup: nil))
        XCTAssertTrue(text.contains("settings timeout"))
        XCTAssertTrue(text.contains("detach error"))
    }
    func testNoErrorAndDuplicateErrorSemantics() throws {
        XCTAssertNil(DXFailurePolicy.description(primary: nil, cleanup: nil))
        XCTAssertTrue(try XCTUnwrap(DXFailurePolicy.description(primary: nil, cleanup: fault("restore"))).contains("restore"))
        let error = fault("same")
        let text = try XCTUnwrap(DXFailurePolicy.description(primary: error, cleanup: error))
        XCTAssertTrue(text.contains("同一错误"))
    }
    func testOnlyBoundedStructuralDiagnosticLabelsAreAccepted() {
        let error = fault("ack timeout", extra: [
            "DXSceneStage": "settings-ack", "DXSceneOperation": "apply",
            "DXSceneSelector": "removeFromSuperview", "DXSceneExceptionName": "NSInternalInconsistencyException",
            "DXSceneReadiness": ["pending": ["process", "events", "/private/user/file", String(repeating: "a", count: 120)]]
        ])
        let text = DXFailurePolicy.detail(error)
        XCTAssertTrue(text.contains("settings-ack"))
        XCTAssertTrue(text.contains("未就绪=process,events"))
        XCTAssertTrue(text.contains("NSInternalInconsistencyException"))
        XCTAssertFalse(text.contains("/private/"))
        XCTAssertFalse(text.contains(String(repeating: "a", count: 120)))
    }
    func testStageGeometryReservesToolbarWithoutChangingSplitPrimitive() throws {
        let bounds = DXRect(x: 0, y: 0, width: 390, height: 844)
        let safe = DXInsets(top: 47, bottom: 34)
        let stage = try XCTUnwrap(DXLayoutPolicy.stage(bounds: bounds, safeArea: safe, ratio: 0.5, gap: 6, margin: 4, radius: 28))
        let plain = try XCTUnwrap(DXLayoutPolicy.split(bounds: bounds, safeArea: safe, ratio: 0.5, gap: 6, margin: 4, radius: 28))
        XCTAssertEqual(stage.bottom.minY - stage.top.maxY, 56, accuracy: 1e-9)
        XCTAssertEqual(plain.bottom.minY - plain.top.maxY, 6, accuracy: 1e-9)
        XCTAssertEqual(stage.topRadius, 28)
        XCTAssertEqual(stage.bottomRadius, 28)
        XCTAssertEqual(DXLayoutPolicy.inputInsets(safe).top, safe.top + 56)
        XCTAssertNil(DXLayoutPolicy.stage(bounds: bounds, safeArea: safe, ratio: 0.5, gap: -.infinity, margin: 4, radius: 28))
    }
}
