import Foundation

public enum DXKeyboardOcclusion: Equatable {
    case none
    case docked(DXRect)
    case floating(DXRect)

    public var frame: DXRect? {
        switch self {
        case .none: return nil
        case .docked(let frame), .floating(let frame): return frame
        }
    }
}

public enum DXKeyboardPolicy {
    public static func occlusion(
        bounds: DXRect, safeArea: DXInsets, keyboard: DXRect, edgeTolerance: Double = 1
    ) -> DXKeyboardOcclusion? {
        guard keyboard.isValid, edgeTolerance.isFinite, edgeTolerance >= 0,
              let usable = bounds.inset(by: safeArea) else { return nil }
        guard keyboard.hasArea, let visible = keyboard.intersection(bounds),
              let blocked = visible.intersection(usable) else {
            // Spell out the enum type: Optional.none would incorrectly signal invalid input.
            return DXKeyboardOcclusion.none
        }
        let reachesBottom = bounds.maxY - visible.maxY <= edgeTolerance
        let coversLeft = visible.minX <= usable.minX || visible.minX - usable.minX <= edgeTolerance
        let coversRight = visible.maxX >= usable.maxX || usable.maxX - visible.maxX <= edgeTolerance
        return reachesBottom && coversLeft && coversRight ? .docked(blocked) : .floating(blocked)
    }

    public static func isDocked(keyboard: DXRect, bounds: DXRect) -> Bool {
        if case .some(.docked(_)) = occlusion(bounds: bounds, safeArea: .zero, keyboard: keyboard) {
            return true
        }
        return false
    }

    /// A nil result for floating/hardware keyboards means retain the split, not full-screen promotion.
    public static func focusedFrame(
        bounds: DXRect, safeArea: DXInsets, keyboard: DXRect, minimumHeight: Double
    ) -> DXRect? {
        guard minimumHeight.isFinite, minimumHeight > 0,
              let usable = bounds.inset(by: safeArea),
              case .some(.docked(let blocked)) = occlusion(
                bounds: bounds, safeArea: safeArea, keyboard: keyboard
              ) else { return nil }
        let height = blocked.minY - usable.minY
        guard height >= minimumHeight else { return nil }
        let result = DXRect(x: usable.x, y: usable.y, width: usable.width, height: height)
        return usable.contains(result) ? result : nil
    }

    /// Subtract only the real obstruction. Bands are disjoint, ordered top/bottom/left/right.
    public static func unobscuredRegions(in frame: DXRect, avoiding keyboard: DXRect) -> [DXRect] {
        guard frame.hasArea, keyboard.isValid else { return [] }
        guard let blocked = frame.intersection(keyboard) else { return [frame] }
        let candidates = [
            DXRect(x: frame.x, y: frame.y, width: frame.width, height: blocked.minY - frame.minY),
            DXRect(x: frame.x, y: blocked.maxY, width: frame.width, height: frame.maxY - blocked.maxY),
            DXRect(x: frame.x, y: blocked.minY, width: blocked.minX - frame.minX, height: blocked.height),
            DXRect(x: blocked.maxX, y: blocked.minY, width: frame.maxX - blocked.maxX, height: blocked.height)
        ]
        return candidates.filter { frame.contains($0) }
    }
}
