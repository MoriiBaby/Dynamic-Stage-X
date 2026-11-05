import UIKit

// Smoke-target ONLY. No bridge, Scene, process, events, readiness or app hosting
// is modeled. This supplies the existing picker's display-record type so that
// the production UIKit stage can be compiled without private frameworks.
final class DXApplicationRecord: NSObject {
    let bundleIdentifier: String
    let displayName: String
    let icon: UIImage?

    init(bundleIdentifier: String, displayName: String, icon: UIImage? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.icon = icon
        super.init()
    }
}
