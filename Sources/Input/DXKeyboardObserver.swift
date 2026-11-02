import UIKit

/// Consumes system notifications only. No keystrokes, text, clipboard or IPC payloads are read.
/// A notification is accepted only when the system confirms the focused PID of a live session.
final class DXKeyboardObserver {
    struct Change {
        let frame: CGRect
        let duration: TimeInterval
        let curve: UIView.AnimationCurve
        let visible: Bool
        let focusPID: pid_t
        let sceneGeneration: UUID
    }
    var resolveFocus: (() -> (pid_t, UUID)?)?
    var onChange: ((Change) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var lastOwner: (pid_t, UUID)?
    private var lastVisible = false

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification,
                     UIResponder.keyboardDidChangeFrameNotification,
                     UIResponder.keyboardWillHideNotification,
                     UIResponder.keyboardDidHideNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.receive(note)
            })
        }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        lastOwner = nil
        lastVisible = false
    }
    deinit { stop() }

    private func receive(_ note: Notification) {
        dispatchPrecondition(condition: .onQueue(.main))
        let info = note.userInfo ?? [:]
        let hiding = note.name == UIResponder.keyboardWillHideNotification ||
            note.name == UIResponder.keyboardDidHideNotification
        let screenFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        guard screenFrame.origin.x.isFinite, screenFrame.origin.y.isFinite,
              screenFrame.width.isFinite, screenFrame.height.isFinite,
              screenFrame.width >= 0, screenFrame.height >= 0 else { return }
        let duration = min(1, max(0, (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25))
        let rawCurve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? 0
        let curve = UIView.AnimationCurve(rawValue: rawCurve) ?? .easeInOut
        let visible = !hiding && screenFrame.height > 0 && screenFrame.intersects(UIScreen.main.bounds)
        let resolved = resolveFocus?()
        // A hide may arrive after the old responder resigned. Reuse its owner only to restore
        // that same generation; the coordinator rejects events for an obsolete generation.
        guard let owner = resolved ?? ((!visible && lastVisible) ? lastOwner : nil), owner.0 > 0 else { return }
        if visible { lastOwner = owner }
        onChange?(Change(frame: visible ? screenFrame : .zero, duration: duration, curve: curve,
                         visible: visible, focusPID: owner.0, sceneGeneration: owner.1))
        lastVisible = visible
        if !visible { lastOwner = nil }
    }
}
