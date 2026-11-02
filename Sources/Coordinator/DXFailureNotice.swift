import UIKit

/// A non-key, noninteractive, short-lived failure notice. It never retains app contents.
final class DXFailureNotice {
    private var window: DXNoticeWindow?
    private var dismissal: DispatchWorkItem?

    func show(_ text: String, in scene: UIWindowScene) {
        dismiss()
        let window = DXNoticeWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.windowLevel = .alert + 1
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        let label = UILabel()
        label.text = "Dynamic Stage X\n" + String(text.prefix(240))
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        label.layer.cornerRadius = 14
        label.layer.cornerCurve = .continuous
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: controller.view.centerXAnchor),
            label.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 18),
            label.widthAnchor.constraint(lessThanOrEqualTo: controller.view.widthAnchor, constant: -32),
            label.widthAnchor.constraint(equalToConstant: 330).withPriority(.defaultHigh),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 70)
        ])
        window.rootViewController = controller
        self.window = window
        window.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: text)
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }
}

private final class DXNoticeWindow: UIWindow {
    override var canBecomeKey: Bool { false }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
