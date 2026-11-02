import Foundation

/// An operation snapshot. Equality checks both the session identity and generation.
public struct DXSessionToken: Hashable {
    public let sessionID: UUID
    public let generation: UInt64

    public init(sessionID: UUID = UUID(), generation: UInt64 = 0) {
        self.sessionID = sessionID
        self.generation = generation
    }
}

public enum DXPhase: String, CaseIterable, Hashable {
    case idle, selecting, preparing, split, inputFocused, collapsed, dismissing
}

/// Value semantics; access on a single serial executor. No scene or UI ownership is implied.
public struct DXStateMachine {
    public private(set) var phase: DXPhase = .idle
    public private(set) var token: DXSessionToken?
    public private(set) var generation: UInt64 = 0
    public private(set) var focusedSlot: DXSlot?
    // Keep two generations available even at exhaustion: beginDismiss, then finishDismiss.
    private static let lastActiveGeneration = UInt64.max - 2
    private var lastFinishedDismissal: DXSessionToken?

    public init() {}

    // Internal restore/test seam: only an idle counter can be seeded, never an active token.
    init(generation: UInt64) { self.generation = generation }

    public func isCurrent(_ token: DXSessionToken) -> Bool {
        phase != .idle && self.token == token
    }

    @discardableResult
    public mutating func beginSelection() -> DXSessionToken? {
        guard phase == .idle, generation < Self.lastActiveGeneration else { return nil }
        generation += 1
        let next = DXSessionToken(generation: generation)
        token = next
        phase = .selecting
        focusedSlot = nil
        lastFinishedDismissal = nil
        return next
    }

    /// Retrying or replacing an app invalidates all callbacks from the previous preparation.
    @discardableResult
    public mutating func prepare(token: DXSessionToken) -> Bool {
        guard isCurrent(token) else { return false }
        switch phase {
        case .selecting, .preparing, .split, .inputFocused, .collapsed:
            return transition(to: .preparing)
        case .idle, .dismissing:
            return false
        }
    }

    @discardableResult
    public mutating func splitReady(token: DXSessionToken) -> Bool {
        guard isCurrent(token), phase == .preparing else { return false }
        return transition(to: .split)
    }

    @discardableResult
    public mutating func focus(token: DXSessionToken, slot: DXSlot) -> Bool {
        guard isCurrent(token), phase == .split || phase == .inputFocused else { return false }
        return transition(to: .inputFocused, slot: slot)
    }

    @discardableResult
    public mutating func clearFocus(token: DXSessionToken) -> Bool {
        guard isCurrent(token) else { return false }
        if phase == .split { return true }
        guard phase == .inputFocused else { return false }
        return transition(to: .split)
    }

    @discardableResult
    public mutating func collapse(token: DXSessionToken) -> Bool {
        guard isCurrent(token) else { return false }
        if phase == .collapsed { return true }
        guard phase == .split || phase == .inputFocused else { return false }
        return transition(to: .collapsed)
    }

    @discardableResult
    public mutating func resume(token: DXSessionToken) -> Bool {
        guard isCurrent(token) else { return false }
        if phase == .split { return true }
        guard phase == .collapsed || phase == .inputFocused else { return false }
        return transition(to: .split)
    }

    @discardableResult
    public mutating func beginDismiss(token: DXSessionToken) -> Bool {
        guard isCurrent(token) else { return false }
        if phase == .dismissing { return true }
        return transition(to: .dismissing)
    }

    @discardableResult
    public mutating func finishDismiss(token: DXSessionToken) -> Bool {
        if phase == .idle {
            return lastFinishedDismissal.map { $0 == token } ?? false
        }
        guard isCurrent(token), phase == .dismissing, generation < UInt64.max else { return false }
        generation += 1
        self.token = nil
        phase = .idle
        focusedSlot = nil
        lastFinishedDismissal = token
        return true
    }

    /// Reserve a new operation generation for work that does not itself change phase.
    @discardableResult
    public mutating func renew(token: DXSessionToken) -> DXSessionToken? {
        guard isCurrent(token), phase != .dismissing,
              transition(to: phase, slot: focusedSlot) else { return nil }
        return self.token
    }

    /// Atomic on failure; generation never wraps and sessions retain their UUID until idle.
    private mutating func transition(to nextPhase: DXPhase, slot: DXSlot? = nil) -> Bool {
        let ceiling = nextPhase == .dismissing ? UInt64.max - 1 : Self.lastActiveGeneration
        guard let current = token, generation < ceiling else { return false }
        generation += 1
        token = DXSessionToken(sessionID: current.sessionID, generation: generation)
        phase = nextPhase
        focusedSlot = slot
        return true
    }
}
