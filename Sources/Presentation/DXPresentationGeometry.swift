import UIKit

/// Shared, deterministic geometry; no private UIKit continuous-corner path is assumed.
internal enum DXContinuousCornerPath {
    static func radius(_ requested: CGFloat, in size: CGSize) -> CGFloat {
        guard requested.isFinite, size.width.isFinite, size.height.isFinite else { return 0 }
        return max(0, min(requested, min(size.width, size.height) / 2))
    }

    static func make(size: CGSize, radius requested: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return path }
        let w = size.width, h = size.height
        let r = radius(requested, in: size), m = r / 5
        // Two cubics per corner. At the straight joins curvature is zero;
        // at each diagonal join both first and second derivatives agree.
        // Always keep the same topology, including r == 0, for path interpolation.
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addCurve(to: CGPoint(x: w - m, y: m),
                      control1: CGPoint(x: w - 4*m, y: 0), control2: CGPoint(x: w - 2*m, y: 0))
        path.addCurve(to: CGPoint(x: w, y: r),
                      control1: CGPoint(x: w, y: 2*m), control2: CGPoint(x: w, y: 4*m))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addCurve(to: CGPoint(x: w - m, y: h - m),
                      control1: CGPoint(x: w, y: h - 4*m), control2: CGPoint(x: w, y: h - 2*m))
        path.addCurve(to: CGPoint(x: w - r, y: h),
                      control1: CGPoint(x: w - 2*m, y: h), control2: CGPoint(x: w - 4*m, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addCurve(to: CGPoint(x: m, y: h - m),
                      control1: CGPoint(x: 4*m, y: h), control2: CGPoint(x: 2*m, y: h))
        path.addCurve(to: CGPoint(x: 0, y: h - r),
                      control1: CGPoint(x: 0, y: h - 2*m), control2: CGPoint(x: 0, y: h - 4*m))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addCurve(to: CGPoint(x: m, y: m),
                      control1: CGPoint(x: 0, y: 4*m), control2: CGPoint(x: 0, y: 2*m))
        path.addCurve(to: CGPoint(x: r, y: 0),
                      control1: CGPoint(x: 2*m, y: 0), control2: CGPoint(x: 4*m, y: 0))
        path.closeSubpath()
        return path
    }

    static func sampledRadius(in path: CGPath) -> CGFloat {
        var result: CGFloat = 0
        var found = false
        path.applyWithBlock { element in
            if !found && element.pointee.type == .moveToPoint {
                result = element.pointee.points[0].x
                found = true
            }
        }
        return result
    }
}

internal enum DXUIGeometry {
    static func valid(_ rect: CGRect) -> Bool {
        return rect.origin.x.isFinite && rect.origin.y.isFinite &&
            rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0 &&
            rect.maxX.isFinite && rect.maxY.isFinite
    }

    static func duration(_ duration: TimeInterval, animated: Bool) -> TimeInterval {
        guard animated, duration.isFinite, duration > 0,
              !UIAccessibility.isReduceMotionEnabled else { return 0 }
        return min(duration, 3)
    }

    static func timing(_ curve: UIView.AnimationCurve) -> CAMediaTimingFunction {
        switch curve {
        case .easeIn: return CAMediaTimingFunction(name: .easeIn)
        case .easeOut: return CAMediaTimingFunction(name: .easeOut)
        case .linear: return CAMediaTimingFunction(name: .linear)
        default: return CAMediaTimingFunction(name: .easeInEaseOut)
        }
    }
}

/// Search tests call this production function, not a parallel test-only filter.
internal enum DXApplicationSearch {
    static func matches(query: String, name: String, bundleIdentifier: String) -> Bool {
        let normalize: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale.current)
        }
        let haystack = normalize(name + "\n" + bundleIdentifier)
        let terms = normalize(query).split(whereSeparator: { $0.isWhitespace })
        return terms.allSatisfy { haystack.contains($0) }
    }
}
