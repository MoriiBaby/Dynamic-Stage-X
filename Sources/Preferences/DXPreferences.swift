import Foundation
import CoreFoundation
import UIKit

struct DXPreferences: Equatable {
    static let domain = "com.tsangbaby.dynamicstagex"
    static let changedNotification = "com.tsangbaby.dynamicstagex/preferences-changed"
    var enabled = false
    var ratio: Double = 0.5
    var cornerRadius: Double = 28
    var gap: Double = 6
    var margin: Double = 4
    var triggerSide = "right"
    var lastApplication: String?

    static func load() -> DXPreferences {
        let domain = Self.domain as CFString
        CFPreferencesAppSynchronize(domain)
        func value(_ key: String) -> Any? {
            CFPreferencesCopyAppValue(key as CFString, domain)
        }
        func number(_ key: String, fallback: Double, range: ClosedRange<Double>) -> Double {
            guard let value = value(key) as? NSNumber, value.doubleValue.isFinite else { return fallback }
            return min(range.upperBound, max(range.lowerBound, value.doubleValue))
        }
        var result = DXPreferences()
        result.enabled = (value("enabled") as? NSNumber)?.boolValue ?? false
        result.ratio = number("ratio", fallback: 0.5, range: 0.35...0.65)
        result.cornerRadius = number("cornerRadius", fallback: 28, range: 12...44)
        result.gap = number("gap", fallback: 6, range: 2...16)
        result.margin = number("margin", fallback: 4, range: 0...12)
        result.triggerSide = (value("triggerSide") as? String) == "left" ? "left" : "right"
        if let identifier = value("lastApplication") as? String, validIdentifier(identifier) {
            result.lastApplication = identifier
        }
        return result
    }

    static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value.contains(".") &&
            value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0) }
    }

    static func rememberApplication(_ identifier: String) {
        guard validIdentifier(identifier) else { return }
        CFPreferencesSetAppValue("lastApplication" as CFString, identifier as CFString, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }
}

extension DXRect {
    init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.width), height: Double(rect.height))
    }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

extension DXInsets {
    init(_ insets: UIEdgeInsets) {
        self.init(top: Double(insets.top), left: Double(insets.left),
                  bottom: Double(insets.bottom), right: Double(insets.right))
    }
}
