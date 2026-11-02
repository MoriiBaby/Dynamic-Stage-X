import UIKit

@_cdecl("DXSwiftStart")
func DXSwiftStart() { DXCoordinator.shared.start() }
@_cdecl("DXSwiftPreferencesChanged")
func DXSwiftPreferencesChanged() { DXCoordinator.shared.preferencesChanged() }
@_cdecl("DXSwiftContextChanged")
func DXSwiftContextChanged() { DXCoordinator.shared.contextChanged() }

/// Main-thread owner of all plugin-created UI and scene leases.
final class DXCoordinator {
    static let shared = DXCoordinator()
    private let bridge = DXSystemBridge.shared()
    private var preferences = DXPreferences.load()
    private var machine = DXStateMachine()
    private var token: DXSessionToken?
    private var generation = UUID()
    private var operation = UUID()
    private var nativeTop: String?
    private var top: DXSystemSceneHandle?
    private var bottom: DXSystemSceneHandle?
    private var overlay: DXOverlayWindow?
    private var stage: DXStageViewController?
    private var trigger: DXEdgeTriggerWindow?
    private var keyboard = DXKeyboardObserver()
    private var observers: [NSObjectProtocol] = []
    private var activeSlot: DXSlot = .top
    private var focusedSlot: DXSlot?
    private var keyboardFrame: CGRect?
    private var layout: DXLayout?
    private var busy = false
    private var dismissing = false
    private var started = false
    private var collapseWork: DispatchWorkItem?
    private var focusOperation = UUID()
    private var geometryRevision: UInt64 = 0
    private var dismissCompletions: [() -> Void] = []
    private var lastCleanupError: Error?
    private let notice = DXFailureNotice()
    private let sceneCommands = DXSceneCommandQueue()

    private init() {}

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !started else { return }
        started = true
        preferences = DXPreferences.load()
        let center = NotificationCenter.default
        for name in [UIApplication.didReceiveMemoryWarningNotification,
                     UIApplication.willResignActiveNotification,
                     Notification.Name("com.tsangbaby.dynamicstagex/scene-invalidated")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // System context changes must never relaunch our previous app over Home,
                // the switcher, another application, or the lock screen.
                self?.dismiss()
            })
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observers.append(center.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.contextChanged()
        })
        keyboard.resolveFocus = { [weak self] in self?.resolveKeyboardOwner() }
        keyboard.onChange = { [weak self] change in self?.keyboardChanged(change) }
        keyboard.start()
        rebuildTrigger()
    }

    func preferencesChanged() {
        dispatchPrecondition(condition: .onQueue(.main))
        preferences = DXPreferences.load()
        if !preferences.enabled { dismiss() }
        if stage != nil && !dismissing { updateLayout(animated: true) }
        rebuildTrigger()
    }

    func contextChanged() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard preferences.enabled, !bridge.isLocked(), let scene = displayScene(), scene.interfaceOrientation.isPortrait else {
            dismiss()
            trigger?.isHidden = true
            return
        }
        if let top = top, !top.isValid { dismiss(); return }
        if let bottom = bottom, !bottom.isValid { dismiss(); return }
        if let front = bridge.frontmostApplicationIdentifier(), stage != nil,
           front != nativeTop && front != bottom?.bundleIdentifier {
            dismiss()
            return
        }
        if overlay != nil { updateLayout(animated: false) }
        rebuildTrigger()
    }

    private func displayScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter {
            $0.activationState == .foregroundActive && $0.screen === UIScreen.main
        }
        // Do not silently take a random scene in a multi-scene SpringBoard configuration.
        return scenes.count == 1 ? scenes[0] : nil
    }

    private func rebuildTrigger() {
        guard preferences.enabled, !bridge.isLocked(), let scene = displayScene(), scene.interfaceOrientation.isPortrait else {
            trigger?.isHidden = true
            return
        }
        if trigger?.windowScene !== scene {
            trigger?.isHidden = true
            let window = DXEdgeTriggerWindow(windowScene: scene)
            window.windowLevel = .statusBar + 2
            window.onTrigger = { [weak self] in self?.triggered() }
            trigger = window
        }
        trigger?.triggerSide = preferences.triggerSide
        trigger?.frame = scene.screen.bounds
        trigger?.isHidden = dismissing || (stage != nil && machine.phase != .collapsed)
    }

    private func triggered() {
        if machine.phase == .collapsed { resume(); return }
        guard !busy, !dismissing, overlay == nil, preferences.enabled,
              !bridge.isLocked(), let scene = displayScene(), scene.interfaceOrientation.isPortrait,
              let identifier = bridge.frontmostApplicationIdentifier(),
              DXPreferences.validIdentifier(identifier), identifier != "com.apple.springboard",
              machine.phase == .idle else { return }
        guard machine.beginSelection() != nil else { return }
        token = machine.token
        beginSession(topIdentifier: identifier, desiredBottom: nil, in: scene)
    }

    private func beginSession(topIdentifier identifier: String, desiredBottom: String?, in scene: UIWindowScene) {
        guard token != nil else { return }
        sceneCommands.resume()
        generation = UUID()
        operation = UUID()
        let expected = generation
        nativeTop = identifier
        activeSlot = .top
        busy = true
        bridge.acquireScene(bundleIdentifier: identifier) { [weak self] handle, error in
            guard let self = self else { return }
            guard self.isCurrent(expected) else { if let handle = handle { self.releaseDetached(handle) }; return }
            guard let handle = handle, error == nil, handle.isValid else {
                self.fail(error?.localizedDescription ?? "无法取得当前应用的真实场景")
                return
            }
            self.top = handle
            let controller = DXStageViewController()
            controller.onClose = { [weak self] in self?.dismiss() }
            controller.onCollapse = { [weak self] in self?.collapse() }
            controller.onChooseApplication = { [weak self] in self?.showPicker() }
            controller.onSwitchInput = { [weak self] in self?.switchInput() }
            controller.onFocus = { [weak self] slot in self?.requestFocus(slot) }
            controller.loadViewIfNeeded()
            controller.view.backgroundColor = .black
            controller.topPane.install(handle.hostView)
            let window = DXOverlayWindow(windowScene: scene)
            window.frame = scene.screen.bounds
            window.windowLevel = .statusBar + 1
            window.rootViewController = controller
            self.stage = controller
            self.overlay = window
            self.busy = false
            // The system's native event binder requires a visible UIWindow. Until ready,
            // the window refuses user interaction until the real presenter acknowledges readiness.
            window.isUserInteractionEnabled = false
            window.isHidden = false
            if let desiredBottom = desiredBottom {
                guard self.transition({ $0.prepare(token: $1) }) else { self.fail("无法建立双窗准备状态"); return }
                self.busy = true
                self.bridge.acquireScene(bundleIdentifier: desiredBottom) { [weak self] lower, lowerError in
                    guard let self = self else { return }
                    guard self.isCurrent(expected) else { if let lower = lower { self.releaseDetached(lower) }; return }
                    guard let lower = lower, lowerError == nil, lower.isValid else {
                        self.fail(lowerError?.localizedDescription ?? "冷启动后的应用场景不可用"); return
                    }
                    self.bottom = lower
                    controller.bottomPane.install(lower.hostView)
                    self.finishInitialLayout(expected: expected, in: window, paired: true)
                }
            } else {
                self.finishInitialLayout(expected: expected, in: window, paired: false)
            }
        }
    }

    private func finishInitialLayout(expected: UUID, in window: DXOverlayWindow, paired: Bool) {
        updateLayout(animated: false) { [weak self] success in
            guard let self = self, self.isCurrent(expected), success else { return }
            self.busy = false
            window.isUserInteractionEnabled = true
            if paired {
                guard self.transition({ $0.splitReady(token: $1) }) else { self.fail("双窗准备结果已过期"); return }
                if let identifier = self.bottom?.bundleIdentifier { DXPreferences.rememberApplication(identifier) }
                self.requestFocus(.bottom)
            } else {
                self.stage?.topPane.acceptsHostedTouches = false
                self.showPicker()
            }
            self.rebuildTrigger()
        }
    }

    private func transition(_ change: (inout DXStateMachine, DXSessionToken) -> Bool) -> Bool {
        guard let current = token, machine.isCurrent(current), change(&machine, current) else { return false }
        token = machine.token
        return true
    }

    private func isCurrent(_ expected: UUID) -> Bool {
        generation == expected && !dismissing && token.map { machine.isCurrent($0) } == true
    }

    private func showPicker() {
        guard !busy, !dismissing, let stage = stage, let identifier = nativeTop else { return }
        if focusedSlot != nil { leaveInputLayout(animated: false) }
        stage.showPicker(applications: bridge.applications(), excluding: identifier) { [weak self] bundle in
            self?.selectApplication(bundle)
        }
    }

    private func selectApplication(_ identifier: String, allowColdLaunch: Bool = true) {
        guard DXPreferences.validIdentifier(identifier), identifier != nativeTop,
              !busy, !dismissing, token != nil else { return }
        if bottom?.bundleIdentifier == identifier { stage?.dismissPicker(); return }
        guard machine.phase == .selecting || machine.phase == .split || machine.phase == .inputFocused else { return }
        // Replacement is transactional: keep old lease and content until the new one is ready.
        if machine.phase == .selecting && !transition({ $0.prepare(token: $1) }) { return }
        busy = true
        operation = UUID()
        let currentOperation = operation
        let expected = generation
        bridge.acquireScene(bundleIdentifier: identifier) { [weak self] handle, error in
            guard let self = self else { return }
            guard self.isCurrent(expected), self.operation == currentOperation else {
                if let handle = handle { self.releaseDetached(handle) }
                return
            }
            guard let handle = handle, error == nil, handle.isValid, let layout = self.layout else {
                self.busy = false
                let nsError = error as NSError?
                if allowColdLaunch, nsError?.domain == "com.tsangbaby.dynamicstagex.system",
                   nsError?.code == 4, let original = self.nativeTop {
                    self.launchColdApplication(identifier, preservingTop: original)
                } else if self.bottom == nil { self.fail(error?.localizedDescription ?? "应用场景准备失败") }
                else { self.stage?.showMessage(error?.localizedDescription ?? "无法更换应用，原窗口已保留") }
                return
            }
            guard let stage = self.stage else { self.releaseDetached(handle); return }
            // The native presenter requires a UIWindow-backed hierarchy before event binding.
            // Stage new real content behind the picker without removing the current bottom pane.
            let staging = UIView(frame: layout.bottom.cgRect)
            staging.clipsToBounds = true
            staging.isUserInteractionEnabled = false
            staging.alpha = 0
            stage.view.addSubview(staging)
            staging.addSubview(handle.hostView)
            handle.hostView.frame = staging.bounds
            self.apply(frame: layout.bottom.cgRect, to: handle) { [weak self] frameError in
                defer { staging.removeFromSuperview() }
                guard let self = self else { return }
                guard self.isCurrent(expected), self.operation == currentOperation else { self.releaseDetached(handle); return }
                guard frameError == nil else {
                    self.releaseDetached(handle)
                    self.busy = false
                    if self.bottom == nil { self.fail(frameError!.localizedDescription) }
                    else { self.stage?.showMessage(frameError!.localizedDescription) }
                    return
                }
                let previous = self.bottom
                self.stage?.bottomPane.detach()
                self.bottom = handle
                self.stage?.bottomPane.install(handle.hostView)
                self.stage?.dismissPicker()
                if self.machine.phase == .preparing { _ = self.transition { $0.splitReady(token: $1) } }
                DXPreferences.rememberApplication(identifier)
                let finishReplacement = { [weak self] in
                    guard let self = self, self.isCurrent(expected), self.operation == currentOperation else { return }
                    self.busy = false
                    self.updateLayout(animated: true) { [weak self] ready in
                        guard let self = self, ready, self.isCurrent(expected) else { return }
                        self.requestFocus(.bottom)
                    }
                }
                if let previous = previous {
                    self.bridge.release(previous) { _ in finishReplacement() }
                } else {
                    finishReplacement()
                }
            }
        }
    }

    private func launchColdApplication(_ identifier: String, preservingTop original: String) {
        // Fallback uses the OS normal launch only after restoring all leases. It may show
        // a brief native launch transition; it never guesses a scene-creation private ABI.
        dismiss() { [weak self] in
            guard let self = self, self.lastCleanupError == nil,
                  self.preferences.enabled, !self.bridge.isLocked() else { return }
            let request = UUID()
            self.operation = request
            self.busy = true
            self.bridge.activateNative(bundleIdentifier: identifier) { [weak self] error in
                guard let self = self, self.operation == request else { return }
                self.busy = false
                guard error == nil, self.preferences.enabled, !self.bridge.isLocked(),
                      self.bridge.frontmostApplicationIdentifier() == identifier,
                      let scene = self.displayScene(), scene.interfaceOrientation.isPortrait,
                      self.machine.beginSelection() != nil else {
                    if let error = error, let scene = self.displayScene() { self.notice.show(error.localizedDescription, in: scene) }
                    return
                }
                self.token = self.machine.token
                self.beginSession(topIdentifier: original, desiredBottom: identifier, in: scene)
            }
        }
    }

    private var geometrySerial: UInt64 {
        get { geometryRevision }
        set { geometryRevision = newValue }
    }
    private func apply(frame: CGRect, to handle: DXSystemSceneHandle, completion: @escaping (Error?) -> Void) {
        sceneCommands.apply(frame: frame, to: handle, bridge: bridge, completion: completion)
    }

    private func handle(for slot: DXSlot) -> DXSystemSceneHandle? { slot == .top ? top : bottom }

    private func updateLayout(animated: Bool, completion: ((Bool) -> Void)? = nil) {
        guard !dismissing, let window = overlay, let stage = stage,
              window.bounds.width > 0, window.bounds.height > 0 else { completion?(false); return }
        window.layoutIfNeeded()
        let insets = window.safeAreaInsets
        guard let next = DXLayoutPolicy.split(bounds: DXRect(window.bounds), safeArea: DXInsets(insets),
                ratio: preferences.ratio, gap: preferences.gap, margin: preferences.margin,
                radius: preferences.cornerRadius) else { fail("当前显示区域不足以建立上下分屏"); completion?(false); return }
        let firstLayout = layout == nil
        layout = next
        if firstLayout {
            stage.setFrames(top: next.top.cgRect, bottom: next.bottom.cgRect,
                topRadius: CGFloat(next.topRadius), bottomRadius: CGFloat(next.bottomRadius),
                animated: false, duration: 0, curve: .easeInOut)
        }
        geometrySerial &+= 1
        let revision = geometrySerial
        let expected = generation
        var requests: [(DXSystemSceneHandle, CGRect)] = []
        if let top = top { requests.append((top, next.top.cgRect)) }
        if let bottom = bottom { requests.append((bottom, next.bottom.cgRect)) }
        if let slot = focusedSlot, let keyboardFrame = keyboardFrame,
           let focused = DXKeyboardPolicy.focusedFrame(bounds: DXRect(window.bounds), safeArea: DXInsets(insets),
                   keyboard: DXRect(keyboardFrame), minimumHeight: 180)?.cgRect,
           let active = handle(for: slot) {
            requests = [(active, focused)]
        }
        let group = DispatchGroup()
        var firstError: Error?
        for (handle, frame) in requests {
            group.enter()
            apply(frame: frame, to: handle) { error in
                if let error = error, firstError == nil { firstError = error }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self, weak stage] in
            guard let self = self, let stage = stage, self.isCurrent(expected), self.geometrySerial == revision else {
                completion?(false); return
            }
            if let error = firstError { self.fail(error.localizedDescription); completion?(false); return }
            stage.setFrames(top: next.top.cgRect, bottom: next.bottom.cgRect,
                topRadius: CGFloat(next.topRadius), bottomRadius: CGFloat(next.bottomRadius),
                animated: animated, duration: 0.3, curve: .easeInOut)
            if let slot = self.focusedSlot, let frame = self.keyboardFrame,
               let focused = DXKeyboardPolicy.focusedFrame(bounds: DXRect(window.bounds), safeArea: DXInsets(insets),
                       keyboard: DXRect(frame), minimumHeight: 180) {
                stage.setInputFocused(slot, frame: focused.cgRect, animated: animated, duration: 0.25, curve: .easeInOut)
            }
            completion?(true)
        }
    }

    private func requestFocus(_ slot: DXSlot) {
        guard !busy, !dismissing, let handle = handle(for: slot), handle.isValid else { return }
        focusOperation = UUID()
        let request = focusOperation
        let expected = generation
        sceneCommands.focus(handle, bridge: bridge) { [weak self] error in
            guard let self = self, self.isCurrent(expected), self.focusOperation == request else { return }
            if let error = error {
                if !handle.isValid { self.fail("应用输入会话已失效：" + error.localizedDescription) }
                else { self.stage?.showMessage("无法确认应用输入焦点：\(error.localizedDescription)") }
                return
            }
            self.activeSlot = slot
        }
    }

    private func resolveKeyboardOwner() -> (pid_t, UUID)? {
        guard !dismissing, machine.phase == .split || machine.phase == .inputFocused else { return nil }
        let pid = bridge.keyboardFocusProcessIdentifier()
        guard pid > 0 else { return nil }
        let owners = [top, bottom].compactMap { $0 }.filter { $0.isValid && $0.processIdentifier == pid }
        return owners.count == 1 ? (pid, generation) : nil
    }

    private func keyboardChanged(_ change: DXKeyboardObserver.Change) {
        guard change.sceneGeneration == generation, !dismissing,
              token != nil, let window = overlay else { return }
        guard change.visible else { leaveInputLayout(animated: true); return }
        let candidates: [(DXSlot, DXSystemSceneHandle?)] = [(.top, top), (.bottom, bottom)]
        let matching = candidates.filter { $0.1?.processIdentifier == change.focusPID && $0.1?.isValid == true }
        guard matching.count == 1, let handle = matching[0].1 else { return }
        let slot = matching[0].0
        let frame = window.convert(change.frame, from: window.screen.coordinateSpace)
        // Floating keyboards only occlude a local region. Let UIKit scroll the responder;
        // do not turn a small floating rect into a full-width desktop reservation.
        guard DXKeyboardPolicy.isDocked(keyboard: DXRect(frame), bounds: DXRect(window.bounds)) else {
            if focusedSlot != nil { leaveInputLayout(animated: true) }
            return
        }
        guard let available = DXKeyboardPolicy.focusedFrame(bounds: DXRect(window.bounds),
            safeArea: DXInsets(window.safeAreaInsets), keyboard: DXRect(frame), minimumHeight: 180) else {
            nativeInputFallback(handle)
            return
        }
        guard transition({ $0.focus(token: $1, slot: slot) }) else { return }
        focusedSlot = slot
        activeSlot = slot
        keyboardFrame = frame
        geometrySerial &+= 1
        let revision = geometrySerial
        let expected = generation
        apply(frame: available.cgRect, to: handle) { [weak self] error in
            guard let self = self, self.isCurrent(expected), self.geometrySerial == revision else { return }
            guard error == nil else { self.nativeInputFallback(handle); return }
            self.stage?.setInputFocused(slot, frame: available.cgRect, animated: true,
                                        duration: change.duration, curve: change.curve)
        }
    }

    private func leaveInputLayout(animated: Bool) {
        guard focusedSlot != nil, token != nil else { return }
        focusedSlot = nil
        keyboardFrame = nil
        _ = transition { $0.clearFocus(token: $1) }
        stage?.setInputFocused(nil, frame: nil, animated: animated, duration: 0.25, curve: .easeInOut)
        updateLayout(animated: animated)
    }

    private func switchInput() {
        guard focusedSlot != nil else { return }
        let other: DXSlot = activeSlot == .top ? .bottom : .top
        guard handle(for: other) != nil else { return }
        // Expose the other app before asking it to become active. A mere toolbar tap is not
        // interpreted as a keyboard-ownership acknowledgment.
        leaveInputLayout(animated: true)
        requestFocus(other)
    }

    private func nativeInputFallback(_ handle: DXSystemSceneHandle) {
        let identifier = handle.bundleIdentifier
        dismiss() { [weak self] in
            guard let self = self, self.lastCleanupError == nil else { return }
            self.bridge.activateNative(bundleIdentifier: identifier) { [weak self] error in
                guard let self = self, let error = error, let scene = self.displayScene(), !self.bridge.isLocked() else { return }
                self.notice.show(error.localizedDescription, in: scene)
            }
        }
    }

    private func collapse() {
        guard !busy, !dismissing, machine.phase == .split,
              token != nil, let top = top, let window = overlay,
              transition({ $0.collapse(token: $1) }) else { return }
        collapseWork?.cancel()
        geometrySerial &+= 1
        let expected = generation
        apply(frame: window.bounds, to: top) { [weak self] error in
            guard let self = self, self.isCurrent(expected), self.machine.phase == .collapsed else { return }
            guard error == nil else { self.fail(error!.localizedDescription); return }
            self.stage?.setInputFocused(.top, frame: window.bounds, animated: true, duration: 0.3, curve: .easeInOut)
            self.stage?.topPane.radius = 0
            self.requestFocus(.top)
            self.rebuildTrigger()
        }
        // A collapsed secondary app is not granted indefinite background residence.
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isCurrent(expected), self.machine.phase == .collapsed else { return }
            self.dismiss()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    private func resume() {
        guard !busy, !dismissing, top?.isValid == true, bottom?.isValid == true,
              transition({ $0.resume(token: $1) }) else { return }
        collapseWork?.cancel()
        collapseWork = nil
        stage?.setInputFocused(nil, frame: nil, animated: false, duration: 0, curve: .easeInOut)
        updateLayout(animated: true)
        rebuildTrigger()
    }

    private func releaseDetached(_ handle: DXSystemSceneHandle) {
        bridge.release(handle) { _ in }
    }

    private func fail(_ message: String) {
        // Keep the reason visible only when a valid UI already exists. Never attach a fake
        // placeholder scene to make a failed capability appear to have succeeded.
        stage?.showMessage(message)
        if let scene = displayScene(), !bridge.isLocked() { notice.show(message, in: scene) }
        dismiss()
    }

    func dismiss(completion: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let completion = completion { dismissCompletions.append(completion) }
        guard !dismissing else { return }
        guard token != nil || overlay != nil || top != nil || bottom != nil else {
            let callbacks = dismissCompletions
            dismissCompletions.removeAll()
            callbacks.forEach { $0() }
            return
        }
        dismissing = true
        lastCleanupError = nil
        busy = false
        generation = UUID()
        operation = UUID()
        focusOperation = UUID()
        geometrySerial &+= 1
        sceneCommands.cancelPending()
        collapseWork?.cancel()
        collapseWork = nil
        _ = transition { $0.beginDismiss(token: $1) }
        let oldToken = token
        let leases = [bottom, top].compactMap { $0 }
        let oldStage = stage
        let oldWindow = overlay
        stage?.dismissPicker()
        stage?.topPane.detach()
        stage?.bottomPane.detach()
        overlay?.isHidden = true
        top = nil
        bottom = nil
        focusedSlot = nil
        keyboardFrame = nil
        layout = nil
        trigger?.isHidden = true
        let group = DispatchGroup()
        for handle in leases {
            group.enter()
            bridge.release(handle) { [weak self] error in
                if self?.lastCleanupError == nil { self?.lastCleanupError = error }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            oldWindow?.rootViewController = nil
            _ = oldStage // Retain the view tree only through the release barrier.
            self.overlay = nil
            self.stage = nil
            if let oldToken = oldToken { _ = self.machine.finishDismiss(token: oldToken) }
            self.token = nil
            self.nativeTop = nil
            self.dismissing = false
            self.rebuildTrigger()
            if let error = self.lastCleanupError, let scene = self.displayScene(), !self.bridge.isLocked() {
                self.notice.show("恢复系统场景时遇到问题：" + error.localizedDescription, in: scene)
            }
            let callbacks = self.dismissCompletions
            self.dismissCompletions.removeAll()
            // Explicit native activation is reserved for the input fallback below. Releasing
            // the top lease restores its system geometry; a generic close never steals focus.
            callbacks.forEach { $0() }
        }
    }
}
