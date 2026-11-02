import Foundation

public struct DXLayout: Equatable {
    public let top: DXRect
    public let bottom: DXRect
    public let topRadius: Double
    public let bottomRadius: Double

    public init(top: DXRect, bottom: DXRect, topRadius: Double, bottomRadius: Double) {
        self.top = top
        self.bottom = bottom
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }
}

public enum DXLayoutPolicy {
    public static func split(
        bounds: DXRect, safeArea: DXInsets, ratio: Double,
        gap: Double, margin: Double, radius: Double
    ) -> DXLayout? {
        guard ratio.isFinite, ratio > 0, ratio < 1,
              gap.isFinite, gap >= 0, margin.isFinite, margin >= 0,
              radius.isFinite, radius >= 0,
              let safe = bounds.inset(by: safeArea),
              let usable = safe.inset(by: DXInsets(top: margin, left: margin, bottom: margin, right: margin)),
              gap < usable.height else { return nil }

        let topHeight = (usable.height - gap) * ratio
        let top = DXRect(x: usable.x, y: usable.y, width: usable.width, height: topHeight)
        let bottomY = top.maxY + gap
        // Derive the last edge from usable bounds rather than accumulating height rounding.
        let bottom = DXRect(
            x: usable.x, y: bottomY, width: usable.width, height: usable.maxY - bottomY
        )
        guard usable.contains(top), usable.contains(bottom), bottom.minY >= top.maxY,
              gap == 0 || bottom.minY > top.maxY,
              top.intersection(bottom) == nil else { return nil }
        return DXLayout(
            top: top, bottom: bottom,
            topRadius: min(radius, min(top.width, top.height) / 2),
            bottomRadius: min(radius, min(bottom.width, bottom.height) / 2)
        )
    }
}
