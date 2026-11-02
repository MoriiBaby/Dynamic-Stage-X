import UIKit

final class DXStageViewController: UIViewController {
    let topPane = DXRoundedPane(frame: .zero)
    let bottomPane = DXRoundedPane(frame: .zero)
    var onClose: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onChooseApplication: (() -> Void)?
    var onSwitchInput: (() -> Void)?
    var onFocus: ((DXSlot) -> Void)?

    internal var hasApplicationPicker: Bool { return picker != nil }
    internal private(set) var inputFocusedSlot: DXSlot?
    private var inputFrame: CGRect?
    private struct SplitLayout {
        let top: CGRect, bottom: CGRect
        let topRadius: CGFloat, bottomRadius: CGFloat
    }
    private var splitLayout: SplitLayout?
    private let chrome = DXStageChrome(frame: .zero)
    private let messageLabel = UILabel()
    private var picker: DXApplicationPickerViewController?
    private var pickerGeneration: UInt64 = 0
    private var animationGeneration: UInt64 = 0
    private var layoutAnimator: UIViewPropertyAnimator?
    private var messageWork: DispatchWorkItem?
    private var messageGeneration: UInt64 = 0

    override func loadView() {
        let root = DXStageRootView(frame: .zero)
        root.backgroundColor = .clear
        root.isOpaque = false
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(topPane)
        view.addSubview(bottomPane)
        view.addSubview(chrome)
        topPane.isHidden = true
        bottomPane.isHidden = true
        topPane.accessibilityIdentifier = "DX.topPane"
        bottomPane.accessibilityIdentifier = "DX.bottomPane"
        topPane.onInteraction = { [weak self] in self?.requestFocus(.top) }
        bottomPane.onInteraction = { [weak self] in self?.requestFocus(.bottom) }
        chrome.closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        chrome.collapseButton.addTarget(self, action: #selector(collapseTapped), for: .touchUpInside)
        chrome.chooseButton.addTarget(self, action: #selector(chooseTapped), for: .touchUpInside)
        chrome.switchInputButton.addTarget(self, action: #selector(switchInputTapped), for: .touchUpInside)
        chrome.switchInputButton.isEnabled = false
        messageLabel.font = .preferredFont(forTextStyle: .callout)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 3
        messageLabel.backgroundColor = .secondarySystemBackground
        messageLabel.textColor = .label
        messageLabel.layer.cornerRadius = 10
        messageLabel.clipsToBounds = true
        messageLabel.isUserInteractionEnabled = false
        messageLabel.isHidden = true
        messageLabel.accessibilityIdentifier = "DX.message"
        view.addSubview(messageLabel)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if layoutAnimator == nil { chrome.frame = targetChromeFrame() }
        layoutMessage()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        suspendInteraction()
    }

    deinit {
        messageWork?.cancel()
        layoutAnimator?.stopAnimation(true)
    }

    func setFrames(top: CGRect, bottom: CGRect, topRadius: CGFloat, bottomRadius: CGFloat,
                   animated: Bool, duration: TimeInterval, curve: UIView.AnimationCurve) {
        precondition(Thread.isMainThread)
        guard DXUIGeometry.valid(top), DXUIGeometry.valid(bottom),
              topRadius.isFinite, bottomRadius.isFinite, topRadius >= 0, bottomRadius >= 0 else {
            showMessage("布局无效，已保留原窗口位置。")
            return
        }
        loadViewIfNeeded()
        splitLayout = SplitLayout(top: top, bottom: bottom,
                                  topRadius: topRadius, bottomRadius: bottomRadius)
        applyLayout(animated: animated, duration: duration, curve: curve)
    }

    func setInputFocused(_ slot: DXSlot?, frame: CGRect?, animated: Bool,
                         duration: TimeInterval, curve: UIView.AnimationCurve) {
        precondition(Thread.isMainThread)
        loadViewIfNeeded()
        if let slot = slot {
            guard splitLayout != nil, let frame = frame, DXUIGeometry.valid(frame) else {
                showMessage("输入区域无效，未改变窗口。")
                return
            }
            inputFocusedSlot = slot
            inputFrame = frame
        } else {
            inputFocusedSlot = nil
            inputFrame = nil
        }
        applyLayout(animated: animated, duration: duration, curve: curve)
    }

    private func applyLayout(animated: Bool, duration: TimeInterval, curve: UIView.AnimationCurve) {
        guard let split = splitLayout else { return }
        let states = interruptAnimation()
        let topVisible: Bool, bottomVisible: Bool
        let topFrame: CGRect, bottomFrame: CGRect
        switch inputFocusedSlot {
        case .some(.top):
            topVisible = true; bottomVisible = false
            topFrame = inputFrame ?? split.top; bottomFrame = split.bottom
        case .some(.bottom):
            topVisible = false; bottomVisible = true
            topFrame = split.top; bottomFrame = inputFrame ?? split.bottom
        case .none:
            topVisible = true; bottomVisible = true
            topFrame = split.top; bottomFrame = split.bottom
        }
        topPane.isHidden = false
        bottomPane.isHidden = false
        // Ignore new hits to the outgoing pane without cancelling an app's
        // already-delivered touches by toggling isUserInteractionEnabled.
        topPane.acceptsHostedTouches = topVisible
        bottomPane.acceptsHostedTouches = bottomVisible
        topPane.accessibilityElementsHidden = !topVisible
        bottomPane.accessibilityElementsHidden = !bottomVisible
        chrome.switchInputButton.isEnabled = inputFocusedSlot != nil
        let seconds = DXUIGeometry.duration(duration, animated: animated && view.window != nil)
        let targetChrome = targetChromeFrame()
        let generation = animationGeneration
        let changes = { [weak self] in
            guard let self = self else { return }
            self.topPane.apply(frame: topFrame, radius: split.topRadius,
                               alpha: topVisible ? 1 : 0, from: states.0.path, duration: seconds, curve: curve)
            self.bottomPane.apply(frame: bottomFrame, radius: split.bottomRadius,
                                  alpha: bottomVisible ? 1 : 0, from: states.1.path, duration: seconds, curve: curve)
            self.chrome.frame = targetChrome
        }
        if seconds == 0 {
            UIView.performWithoutAnimation(changes)
            topPane.isHidden = !topVisible
            bottomPane.isHidden = !bottomVisible
        } else {
            let animator = UIViewPropertyAnimator(duration: seconds, curve: curve, animations: changes)
            animator.addCompletion { [weak self] _ in
                guard let self = self, self.animationGeneration == generation else { return }
                self.layoutAnimator = nil
                self.topPane.isHidden = !topVisible
                self.bottomPane.isHidden = !bottomVisible
                self.chrome.frame = self.targetChromeFrame()
            }
            layoutAnimator = animator
            animator.startAnimation()
        }
    }

    @discardableResult
    private func interruptAnimation() -> (DXRoundedPane.Presentation, DXRoundedPane.Presentation) {
        // Capture BEFORE stopping: stopping first loses the presentation tree.
        let top = topPane.capturePresentation(), bottom = bottomPane.capturePresentation()
        let chromeFrame = chrome.layer.presentation()?.frame ?? chrome.frame
        animationGeneration &+= 1
        layoutAnimator?.stopAnimation(true)
        layoutAnimator = nil
        UIView.performWithoutAnimation {
            self.topPane.freeze(top)
            self.bottomPane.freeze(bottom)
            self.chrome.frame = chromeFrame
        }
        return (top, bottom)
    }

    private func targetChromeFrame() -> CGRect {
        let safe = view.bounds.inset(by: view.safeAreaInsets)
        let width = min(224, max(0, safe.width - 16))
        guard width >= 176, safe.height >= 44, let split = splitLayout else { return .zero }
        var y: CGFloat
        if let frame = inputFrame, inputFocusedSlot != nil {
            y = frame.minY - safe.minY >= 52 ? frame.minY - 52 : frame.minY + 8
        } else {
            y = (split.top.maxY + split.bottom.minY) / 2 - 22
        }
        y = max(safe.minY, min(y, safe.maxY - 44))
        return CGRect(x: safe.midX - width / 2, y: y, width: width, height: 44)
    }

    func showPicker(applications: [DXApplicationRecord], excluding: String?,
                    selection: @escaping (String) -> Void) {
        precondition(Thread.isMainThread)
        loadViewIfNeeded()
        dismissPicker()
        let generation = pickerGeneration
        let controller = DXApplicationPickerViewController(applications: applications, excluding: excluding,
            selection: { [weak self] identifier in
                guard let self = self, self.pickerGeneration == generation, self.picker != nil else { return }
                self.dismissPicker()
                selection(identifier)
            }, cancellation: { [weak self] in
                guard let self = self, self.pickerGeneration == generation else { return }
                self.dismissPicker()
            })
        picker = controller
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        if canDeliverIntent { UIAccessibility.post(notification: .screenChanged, argument: controller.view) }
    }

    /// Optional query from an already trusted caller; never creates a text responder.
    func filterPickerApplications(query: String) {
        precondition(Thread.isMainThread)
        picker?.filterApplications(query: query)
    }

    func dismissPicker() {
        precondition(Thread.isMainThread)
        pickerGeneration &+= 1
        guard let controller = picker else { return }
        picker = nil
        controller.invalidate()
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        if canDeliverIntent { UIAccessibility.post(notification: .screenChanged, argument: chrome.chooseButton) }
    }

    func showMessage(_ text: String) {
        precondition(Thread.isMainThread)
        loadViewIfNeeded()
        messageWork?.cancel()
        messageGeneration &+= 1
        let generation = messageGeneration
        messageLabel.text = text
        messageLabel.isHidden = text.isEmpty
        layoutMessage()
        guard !text.isEmpty else { return }
        if canDeliverIntent { UIAccessibility.post(notification: .announcement, argument: text) }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.messageGeneration == generation else { return }
            self.messageLabel.isHidden = true
        }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func layoutMessage() {
        guard isViewLoaded, !messageLabel.isHidden else { return }
        let safe = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 16, dy: 8)
        guard safe.width > 0, safe.height > 0 else { messageLabel.frame = .zero; return }
        let size = messageLabel.sizeThatFits(CGSize(width: max(0, safe.width - 16), height: 120))
        let height = min(safe.height, max(44, size.height + 16))
        let bottom = min(safe.maxY, inputFrame?.maxY ?? safe.maxY)
        messageLabel.frame = CGRect(x: safe.minX, y: max(safe.minY, bottom - height),
                                    width: safe.width, height: height)
    }

    /// Stops our transient UI only. Parent separately unfocuses/releases real scenes.
    func suspendInteraction() {
        precondition(Thread.isMainThread)
        dismissPicker()
        topPane.cancelPendingInteraction()
        bottomPane.cancelPendingInteraction()
        messageWork?.cancel()
        messageGeneration &+= 1
        if isViewLoaded {
            messageLabel.isHidden = true
            interruptAnimation()
        }
    }

    private var canDeliverIntent: Bool {
        guard let window = viewIfLoaded?.window, !window.isHidden,
              window.isUserInteractionEnabled else { return false }
        if let overlay = window as? DXOverlayWindow, !overlay.isContextEnabled { return false }
        if let scene = window.windowScene, scene.activationState != .foregroundActive { return false }
        return true
    }

    private func requestFocus(_ slot: DXSlot) {
        guard canDeliverIntent, picker == nil else { return }
        onFocus?(slot) // Intent only, NOT a claim of actual system keyboard focus.
    }
    @objc private func closeTapped() {
        guard canDeliverIntent else { return }
        dismissPicker()
        onClose?()
    }
    @objc private func collapseTapped() {
        guard canDeliverIntent else { return }
        dismissPicker()
        onCollapse?()
    }
    @objc private func chooseTapped() {
        guard canDeliverIntent else { return }
        onChooseApplication?()
    }
    @objc private func switchInputTapped() {
        guard canDeliverIntent, inputFocusedSlot != nil else { return }
        onSwitchInput?()
    }
}
