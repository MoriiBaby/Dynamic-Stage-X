import Foundation

/// Input eligibility only. Visibility or a recognized pan does not grant private Scene authority.
public enum DXTriggerBlock: String, CaseIterable {
    case disabled, locked, sceneUnavailable, portraitRequired, busy, dismissing
    case existingOverlay, missingFrontmost, homeScreen, invalidFrontmost, stateConflict
}

public enum DXTriggerEligibility {
    /// Evaluate once for an explicit accepted gesture. No side effects and no OS-version gate.
    public static func denial(enabled: Bool, locked: Bool, hasMainScene: Bool, portrait: Bool,
                              busy: Bool, dismissing: Bool, hasOverlay: Bool,
                              phase: DXPhase, frontmostIdentifier: String?) -> DXTriggerBlock? {
        guard enabled else { return .disabled }
        guard !locked else { return .locked }
        guard hasMainScene else { return .sceneUnavailable }
        guard portrait else { return .portraitRequired }
        guard !dismissing else { return .dismissing }
        guard !busy else { return .busy }
        guard !hasOverlay else { return .existingOverlay }
        guard phase == .idle else { return .stateConflict }
        guard let identifier = frontmostIdentifier, !identifier.isEmpty else { return .missingFrontmost }
        guard identifier != "com.apple.springboard" else { return .homeScreen }
        guard identifier.utf8.count <= 255, identifier.contains("."),
              identifier.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0)
              }) else { return .invalidFrontmost }
        return nil
    }
}
