import Foundation

public enum DXSlot: String, CaseIterable, Hashable {
    case top, bottom
}

public struct DXInsets: Equatable {
    public let top: Double
    public let left: Double
    public let bottom: Double
    public let right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = DXInsets()

    public var isValid: Bool {
        top.isFinite && left.isFinite && bottom.isFinite && right.isFinite
            && top >= 0 && left >= 0 && bottom >= 0 && right >= 0
    }
}

public struct DXRect: Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = DXRect(x: 0, y: 0, width: 0, height: 0)
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var isFinite: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite }
    public var isValid: Bool {
        isFinite && width >= 0 && height >= 0 && maxX.isFinite && maxY.isFinite
    }
    public var hasArea: Bool {
        isValid && width > 0 && height > 0 && maxX > minX && maxY > minY
    }

    public func contains(x: Double, y: Double) -> Bool {
        hasArea && x.isFinite && y.isFinite && x >= minX && x <= maxX && y >= minY && y <= maxY
    }

    public func contains(_ other: DXRect) -> Bool {
        hasArea && other.hasArea && other.minX >= minX && other.maxX <= maxX
            && other.minY >= minY && other.maxY <= maxY
    }

    /// Positive-area intersection. Merely touching edges do not intersect.
    public func intersection(_ other: DXRect) -> DXRect? {
        guard hasArea, other.hasArea else { return nil }
        let left = max(minX, other.minX)
        let top = max(minY, other.minY)
        let right = min(maxX, other.maxX)
        let bottom = min(maxY, other.maxY)
        guard right > left, bottom > top else { return nil }
        let result = DXRect(x: left, y: top, width: right - left, height: bottom - top)
        return contains(result) && other.contains(result) ? result : nil
    }

    public func inset(by insets: DXInsets) -> DXRect? {
        guard hasArea, insets.isValid, insets.left <= width, insets.top <= height else { return nil }
        // Sequential subtraction avoids overflowing sums of otherwise finite insets.
        let remainingWidth = width - insets.left
        let remainingHeight = height - insets.top
        guard insets.right < remainingWidth, insets.bottom < remainingHeight else { return nil }
        let result = DXRect(
            x: x + insets.left, y: y + insets.top,
            width: remainingWidth - insets.right, height: remainingHeight - insets.bottom
        )
        return contains(result) ? result : nil
    }
}

/// Circular corner policy. Match the presentation clipping path when using it.
public enum DXRoundedHitTest {
    public static func contains(x: Double, y: Double, in bounds: DXRect, radius: Double) -> Bool {
        guard bounds.contains(x: x, y: y), radius.isFinite, radius >= 0 else { return false }
        let r = min(radius, min(bounds.width, bounds.height) / 2)
        guard r > 0 else { return true }
        let centerX = min(max(x, bounds.minX + r), bounds.maxX - r)
        let centerY = min(max(y, bounds.minY + r), bounds.maxY - r)
        // Normalizing first avoids overflow when radius and coordinates are large.
        let dx = (x - centerX) / r
        let dy = (y - centerY) / r
        return dx * dx + dy * dy <= 1
    }
}
