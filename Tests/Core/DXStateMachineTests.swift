import Foundation
import XCTest
@testable import DynamicStageXCore

final class DXStateMachineTests: XCTestCase {
    private func machine(in phase: DXPhase) throws -> DXStateMachine {
        var state = DXStateMachine()
        if phase == .idle { return state }
        let selected = try XCTUnwrap(state.beginSelection())
        if phase == .selecting { return state }
        if phase == .dismissing {
            XCTAssertTrue(state.beginDismiss(token: selected))
            return state
        }
        XCTAssertTrue(state.prepare(token: selected))
        if phase == .preparing { return state }
        XCTAssertTrue(state.splitReady(token: try XCTUnwrap(state.token)))
        if phase == .inputFocused {
            XCTAssertTrue(state.focus(token: try XCTUnwrap(state.token), slot: .bottom))
        } else if phase == .collapsed {
            XCTAssertTrue(state.collapse(token: try XCTUnwrap(state.token)))
        }
        return state
    }

    func testWholeLifecycleReplacesOperationTokenAndRetainsSessionIdentity() throws {
        var state = DXStateMachine()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.generation, 0)
        XCTAssertNil(state.token)
        let selected = try XCTUnwrap(state.beginSelection())
        XCTAssertEqual(selected.generation, 1)
        XCTAssertTrue(state.prepare(token: selected))
        let preparing = try XCTUnwrap(state.token)
        XCTAssertEqual(preparing.sessionID, selected.sessionID)
        XCTAssertFalse(state.isCurrent(selected))
        XCTAssertTrue(state.splitReady(token: preparing))
        let split = try XCTUnwrap(state.token)
        XCTAssertTrue(state.focus(token: split, slot: .bottom))
        let bottom = try XCTUnwrap(state.token)
        XCTAssertEqual(state.focusedSlot, .bottom)
        XCTAssertTrue(state.focus(token: bottom, slot: .top))
        let top = try XCTUnwrap(state.token)
        XCTAssertEqual(state.focusedSlot, .top)
        XCTAssertFalse(state.clearFocus(token: bottom))
        XCTAssertTrue(state.clearFocus(token: top))
        XCTAssertEqual(state.phase, .split)
        XCTAssertNil(state.focusedSlot)
        XCTAssertTrue(state.collapse(token: try XCTUnwrap(state.token)))
        let collapsed = try XCTUnwrap(state.token)
        XCTAssertTrue(state.resume(token: collapsed))
        XCTAssertFalse(state.resume(token: collapsed))
        XCTAssertTrue(state.beginDismiss(token: try XCTUnwrap(state.token)))
        let dismissing = try XCTUnwrap(state.token)
        XCTAssertTrue(state.beginDismiss(token: dismissing))
        XCTAssertEqual(state.token, dismissing)
        XCTAssertTrue(state.finishDismiss(token: dismissing))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.token)
        XCTAssertNil(state.focusedSlot)
        XCTAssertFalse(state.isCurrent(dismissing))
        let finalGeneration = state.generation
        XCTAssertTrue(state.finishDismiss(token: dismissing))
        XCTAssertEqual(state.generation, finalGeneration)
    }

    func testImmediateDismissAndLatePreparationCannotReviveSession() throws {
        var state = DXStateMachine()
        let selected = try XCTUnwrap(state.beginSelection())
        XCTAssertTrue(state.prepare(token: selected))
        let preparation = try XCTUnwrap(state.token)
        XCTAssertTrue(state.beginDismiss(token: preparation))
        let closing = try XCTUnwrap(state.token)
        XCTAssertFalse(state.splitReady(token: preparation))
        XCTAssertFalse(state.focus(token: preparation, slot: .top))
        XCTAssertTrue(state.finishDismiss(token: closing))
        let replacement = try XCTUnwrap(state.beginSelection())
        XCTAssertNotEqual(replacement.sessionID, selected.sessionID)
        XCTAssertGreaterThan(replacement.generation, closing.generation)
        XCTAssertFalse(state.finishDismiss(token: closing))
        XCTAssertFalse(state.beginDismiss(token: preparation))
        XCTAssertEqual(state.token, replacement)
    }

    func testRetryAndSameSlotFocusInvalidateOldOperations() throws {
        var state = try machine(in: .preparing)
        let attemptOne = try XCTUnwrap(state.token)
        XCTAssertTrue(state.prepare(token: attemptOne))
        let attemptTwo = try XCTUnwrap(state.token)
        XCTAssertNotEqual(attemptOne, attemptTwo)
        XCTAssertEqual(attemptOne.sessionID, attemptTwo.sessionID)
        XCTAssertFalse(state.splitReady(token: attemptOne))
        XCTAssertTrue(state.splitReady(token: attemptTwo))
        XCTAssertTrue(state.focus(token: try XCTUnwrap(state.token), slot: .top))
        let keyboardOne = try XCTUnwrap(state.token)
        XCTAssertTrue(state.focus(token: keyboardOne, slot: .top))
        let keyboardTwo = try XCTUnwrap(state.token)
        XCTAssertFalse(state.isCurrent(keyboardOne))
        XCTAssertEqual(state.focusedSlot, .top)
        let frameOperation = try XCTUnwrap(state.renew(token: keyboardTwo))
        XCTAssertEqual(frameOperation.generation, keyboardTwo.generation + 1)
        XCTAssertEqual(state.phase, .inputFocused)
        XCTAssertEqual(state.focusedSlot, .top)
        XCTAssertFalse(state.clearFocus(token: keyboardTwo))
        XCTAssertTrue(state.clearFocus(token: frameOperation))
    }

    func testTransitionMatrixAndAtomicRejection() throws {
        typealias Mutation = (inout DXStateMachine, DXSessionToken) -> Bool
        let rules: [(String, Set<DXPhase>, Mutation)] = [
            ("prepare", [.selecting, .preparing, .split, .inputFocused, .collapsed], { $0.prepare(token: $1) }),
            ("splitReady", [.preparing], { $0.splitReady(token: $1) }),
            ("focus", [.split, .inputFocused], { $0.focus(token: $1, slot: .top) }),
            ("clearFocus", [.split, .inputFocused], { $0.clearFocus(token: $1) }),
            ("collapse", [.split, .inputFocused, .collapsed], { $0.collapse(token: $1) }),
            ("resume", [.split, .inputFocused, .collapsed], { $0.resume(token: $1) }),
            ("beginDismiss", [.selecting, .preparing, .split, .inputFocused, .collapsed, .dismissing], { $0.beginDismiss(token: $1) }),
            ("finishDismiss", [.dismissing], { $0.finishDismiss(token: $1) })
        ]
        for phase in DXPhase.allCases {
            for (name, allowed, mutate) in rules {
                var state = try machine(in: phase)
                let token = state.token ?? DXSessionToken()
                let before = state
                XCTAssertEqual(mutate(&state, token), allowed.contains(phase), "\(phase) / \(name)")
                if !allowed.contains(phase) {
                    XCTAssertEqual(state.phase, before.phase)
                    XCTAssertEqual(state.token, before.token)
                    XCTAssertEqual(state.generation, before.generation)
                    XCTAssertEqual(state.focusedSlot, before.focusedSlot)
                }
                XCTAssertEqual(state.focusedSlot != nil, state.phase == .inputFocused)
            }
        }
    }

    func testEveryMutationRejectsWrongUUIDAndWrongGeneration() throws {
        for phase in DXPhase.allCases where phase != .idle {
            let base = try machine(in: phase)
            let current = try XCTUnwrap(base.token)
            for stale in [
                DXSessionToken(sessionID: UUID(), generation: current.generation),
                DXSessionToken(sessionID: current.sessionID, generation: current.generation - 1)
            ] {
                var state = base
                XCTAssertFalse(state.isCurrent(stale))
                XCTAssertFalse(state.prepare(token: stale))
                XCTAssertFalse(state.splitReady(token: stale))
                XCTAssertFalse(state.focus(token: stale, slot: .bottom))
                XCTAssertFalse(state.clearFocus(token: stale))
                XCTAssertFalse(state.collapse(token: stale))
                XCTAssertFalse(state.resume(token: stale))
                XCTAssertFalse(state.beginDismiss(token: stale))
                XCTAssertFalse(state.finishDismiss(token: stale))
                XCTAssertNil(state.renew(token: stale))
                XCTAssertNil(state.beginSelection())
                XCTAssertEqual(state.phase, base.phase)
                XCTAssertEqual(state.token, base.token)
                XCTAssertEqual(state.generation, base.generation)
                XCTAssertEqual(state.focusedSlot, base.focusedSlot)
            }
        }
    }

    func testGenerationExhaustionStillPermitsBoundedDismissalWithoutWrapping() throws {
        var state = DXStateMachine(generation: UInt64.max - 3)
        let lastSelection = try XCTUnwrap(state.beginSelection())
        XCTAssertEqual(lastSelection.generation, UInt64.max - 2)
        XCTAssertFalse(state.prepare(token: lastSelection))
        XCTAssertNil(state.renew(token: lastSelection))
        XCTAssertEqual(state.token, lastSelection)
        XCTAssertTrue(state.beginDismiss(token: lastSelection))
        let dismissal = try XCTUnwrap(state.token)
        XCTAssertEqual(dismissal.generation, UInt64.max - 1)
        XCTAssertTrue(state.finishDismiss(token: dismissal))
        XCTAssertEqual(state.generation, UInt64.max)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.beginSelection())
        XCTAssertTrue(state.finishDismiss(token: dismissal))
        XCTAssertEqual(state.generation, UInt64.max)
    }

    func testIdempotentRequestsAndDismissalCannotBeRenewed() throws {
        var state = try machine(in: .split)
        let split = try XCTUnwrap(state.token)
        XCTAssertTrue(state.resume(token: split))
        XCTAssertTrue(state.clearFocus(token: split))
        XCTAssertEqual(state.token, split)
        XCTAssertTrue(state.collapse(token: split))
        let collapsed = try XCTUnwrap(state.token)
        XCTAssertTrue(state.collapse(token: collapsed))
        XCTAssertEqual(state.token, collapsed)
        XCTAssertTrue(state.beginDismiss(token: collapsed))
        let dismissal = try XCTUnwrap(state.token)
        XCTAssertNil(state.renew(token: dismissal))
        XCTAssertEqual(state.token, dismissal)
        XCTAssertTrue(state.finishDismiss(token: dismissal))
        XCTAssertFalse(state.finishDismiss(token: collapsed))
    }
}
