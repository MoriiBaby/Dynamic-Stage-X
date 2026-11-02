import UIKit

/// Never becomes key, including while the picker is visible. Native Scene/input
/// ownership stays with the coordinator; the picker has no local text responder.
final class DXOverlayWindow: UIWindow {
    var permitsBackgroundHitTesting = false
    var isContextEnabled = true {
        didSet { if !isContextEnabled { suspendInteraction() } }
    }
    override var isHidden: Bool {
        didSet { if isHidden { suspendInteraction() } }
    }
    override var isUserInteractionEnabled: Bool {
        didSet { if !isUserInteractionEnabled { suspendInteraction() } }
    }
    override var canBecomeKey: Bool { return false }
    private var observations: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        accessibilityIdentifier = "DX.overlay"
        let names: [Notification.Name] = [UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification, UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification]
        for name in names {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                                                                        queue: .main) { [weak self] note in
                guard let self = self else { return }
                if let scene = note.object as? UIScene, scene !== self.windowScene { return }
                self.suspendInteraction()
            })
        }
    }

    deinit {
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
    }

    private var contextIsUsable: Bool {
        return isContextEnabled && !isHidden && alpha > 0.01 && isUserInteractionEnabled &&
            windowScene?.activationState == .foregroundActive
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard contextIsUsable else { return nil }
        let hit = super.hitTest(point, with: event)
        if hit === self || hit === rootViewController?.view {
            return permitsBackgroundHitTesting ? hit : nil
        }
        if let hit = hit { return hit }
        return permitsBackgroundHitTesting && bounds.contains(point) ? self : nil
    }

    /// Parent must hide/disable this on lock, switcher, Control Center, etc., and
    /// separately release remote input. This method never changes native focus.
    func suspendInteraction() {
        precondition(Thread.isMainThread)
        (rootViewController as? DXStageViewController)?.suspendInteraction()
    }
}
