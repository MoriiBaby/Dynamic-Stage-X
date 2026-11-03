import UIKit

internal enum DXEdgeTriggerPolicy {
    static func region(bounds: CGRect, safeArea: UIEdgeInsets, side: String) -> CGRect {
        guard DXUIGeometry.valid(bounds),
              [safeArea.top, safeArea.left, safeArea.bottom, safeArea.right].allSatisfy({ $0.isFinite && $0 >= 0 })
        else { return .zero }
        let usable = bounds.inset(by: safeArea)
        guard usable.width >= 64, usable.height >= 112 else { return .zero }
        // Reserve a forgiving corner strip above the Home indicator. The visible mark stays
        // much smaller; the hit target is 64×88pt so a bottom-corner swipe is not pixel-precise.
        let x = side == "left" ? usable.minX : usable.maxX - 64
        return CGRect(x: x, y: usable.maxY - 96, width: 64, height: 88)
    }

    static func mayBegin(translation: CGPoint, velocity: CGPoint) -> Bool {
        guard finite(translation), finite(velocity) else { return false }
        // UIPan owns the initial slop threshold. Its delegate can be asked before a
        // useful translation/velocity sample is exposed (including zero/zero). Never
        // permanently fail that undecided first sample; decide upward intent at release.
        return true
    }

    static func mayFinish(translation: CGPoint, velocity: CGPoint, elapsed: TimeInterval) -> Bool {
        guard finite(translation), finite(velocity), elapsed.isFinite else { return false }
        // elapsed is recognition-to-release, not touch-down-to-release. A deliberate
        // fast swipe must not fail merely because UIKit recognized it near the end.
        return elapsed >= 0 && elapsed <= 2.8 && translation.y <= -48 &&
            abs(translation.x) <= max(52, -translation.y * 0.9) && velocity.y <= 220
    }

    private static func finite(_ point: CGPoint) -> Bool { return point.x.isFinite && point.y.isFinite }
}

private final class DXEdgeHandle: UIView {
    var activate: (() -> Bool)?
    private let indicator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "打开 Dynamic Stage X"
        accessibilityHint = "在这个小区域向上滑动，选择下方应用"
        accessibilityIdentifier = "DX.edgeTrigger"
        indicator.backgroundColor = UIColor.label.withAlphaComponent(0.45)
        indicator.layer.cornerRadius = 3
        indicator.isUserInteractionEnabled = false
        addSubview(indicator)
    }
    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        indicator.frame = CGRect(x: bounds.midX - 3, y: bounds.midY - 14, width: 6, height: 28)
    }
    func showTracking(_ active: Bool) {
        indicator.backgroundColor = active ? .systemBlue : UIColor.label.withAlphaComponent(0.45)
        accessibilityValue = active ? "正在识别上滑" : "等待上滑"
    }
    override func accessibilityActivate() -> Bool { return activate?() ?? false }
}

private final class DXEdgeRootView: UIView {
    let handle = DXEdgeHandle(frame: .zero)
    var side = "right" { didSet { setNeedsLayout() } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(handle)
    }
    required init?(coder: NSCoder) { return nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        handle.frame = DXEdgeTriggerPolicy.region(bounds: bounds, safeArea: safeAreaInsets, side: side)
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01, handle.frame.contains(point) else { return nil }
        return handle.hitTest(handle.convert(point, from: self), with: event)
    }
}

/// Full-window coordinates are allowed, but the only interactive area is 64 x 88pt.
/// Parent owns visibility and system-context gating; this window can never be key.
final class DXEdgeTriggerWindow: UIWindow, UIGestureRecognizerDelegate {
    var onTrigger: (() -> Void)?
    /// Bounded stage feedback only; no coordinates, touch histories or app contents.
    var onGestureFeedback: ((String) -> Void)?
    var triggerSide: String {
        get { return edgeRoot.side }
        set {
            precondition(Thread.isMainThread)
            let normalized = newValue.lowercased() == "left" ? "left" : "right"
            guard normalized != edgeRoot.side else { return }
            resetTracking(cancelRecognizer: true)
            edgeRoot.side = normalized
        }
    }
    var isContextEnabled = true {
        didSet { if !isContextEnabled { resetTracking(cancelRecognizer: true) } }
    }
    override var isHidden: Bool {
        didSet { if isHidden { resetTracking(cancelRecognizer: true) } }
    }
    override var isUserInteractionEnabled: Bool {
        didSet { if !isUserInteractionEnabled { resetTracking(cancelRecognizer: true) } }
    }
    override var canBecomeKey: Bool { return false }

    private let edgeRoot = DXEdgeRootView(frame: .zero)
    private var beganAt: TimeInterval?
    private var isConfigured = false
    private var observations: [NSObjectProtocol] = []
    private lazy var pan: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.minimumNumberOfTouches = 1
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        return recognizer
    }()

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
        let controller = UIViewController()
        controller.view = edgeRoot
        rootViewController = controller
        edgeRoot.handle.addGestureRecognizer(pan)
        edgeRoot.handle.activate = { [weak self] in
            guard let self = self, self.contextIsUsable else { return false }
            self.onTrigger?() // Explicit VoiceOver activation, never an ordinary tap.
            return true
        }
        isConfigured = true
        let names: [Notification.Name] = [UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification, UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification]
        for name in names {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil,
                                                                        queue: .main) { [weak self] note in
                guard let self = self else { return }
                if let scene = note.object as? UIScene, scene !== self.windowScene { return }
                self.resetTracking(cancelRecognizer: true)
            })
        }
    }

    deinit {
        for observation in observations { NotificationCenter.default.removeObserver(observation) }
    }

    private var contextIsUsable: Bool {
        return isContextEnabled && !isHidden && isUserInteractionEnabled && alpha > 0.01 &&
            windowScene?.activationState == .foregroundActive
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard contextIsUsable else { return nil }
        edgeRoot.layoutIfNeeded()
        return edgeRoot.hitTest(edgeRoot.convert(point, from: self), with: event)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        guard contextIsUsable else { onGestureFeedback?("context-rejected"); return false }
        let permitted = DXEdgeTriggerPolicy.mayBegin(translation: pan.translation(in: self), velocity: pan.velocity(in: self))
        if !permitted { onGestureFeedback?("begin-rejected") }
        return permitted
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return contextIsUsable && touch.type == .direct
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard contextIsUsable else { resetTracking(cancelRecognizer: true); return }
        switch recognizer.state {
        case .began:
            beganAt = ProcessInfo.processInfo.systemUptime
            edgeRoot.handle.showTracking(true)
            onGestureFeedback?("began")
        case .ended:
            let elapsed = beganAt.map { ProcessInfo.processInfo.systemUptime - $0 }
            let accepted = elapsed.map {
                DXEdgeTriggerPolicy.mayFinish(translation: recognizer.translation(in: self),
                                              velocity: recognizer.velocity(in: self), elapsed: $0)
            } ?? false
            resetTracking(cancelRecognizer: false)
            if accepted, contextIsUsable {
                onGestureFeedback?("accepted")
                onTrigger?()
            } else {
                onGestureFeedback?("release-rejected")
            }
        case .cancelled, .failed:
            resetTracking(cancelRecognizer: false)
            onGestureFeedback?("cancelled")
        default: break
        }
    }

    private func resetTracking(cancelRecognizer: Bool) {
        beganAt = nil
        edgeRoot.handle.showTracking(false)
        guard isConfigured, cancelRecognizer, pan.isEnabled else { return }
        // Cancel only OUR recognizer. UIKit cannot replay an already-delivered
        // touch stream to an underlying window; the reservation is deliberately tiny.
        pan.isEnabled = false
        pan.isEnabled = true
    }
}
