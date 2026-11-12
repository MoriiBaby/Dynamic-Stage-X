import UIKit

/// Shared by XCTest and the tiny executable. Exercises production UIKit objects;
/// local UIView hosts below are test views, NOT native/remote app hosting proof.
enum DXStageAlpha4Checks {
    static func run(in window: UIWindow) -> (checks: Int, failures: [String]) {
        precondition(Thread.isMainThread)
        var count = 0
        var failures: [String] = []
        func check(_ success: Bool, _ message: String) {
            count += 1
            if !success { failures.append(message) }
        }
        let stage = (window.rootViewController as? DXStageViewController) ?? DXStageViewController()
        if window.rootViewController !== stage { window.rootViewController = stage }
        window.isHidden = false
        stage.loadViewIfNeeded()
        check(stage.view.window === window, "test stage is not attached to the visible test window")
        check(window.windowScene?.activationState == .foregroundActive,
              "test requires an actual foreground-active UIKit scene")
        stage.view.frame = window.bounds
        stage.view.setNeedsLayout()
        stage.view.layoutIfNeeded()
        let safe = stage.view.bounds.inset(by: stage.view.safeAreaInsets)
        let top = CGRect(x: safe.minX + 8, y: safe.minY + 8,
                         width: safe.width - 16, height: 240)
        let bottom = CGRect(x: top.minX, y: top.maxY + 56, width: top.width, height: 240)
        func layout(_ bottomFrame: CGRect) {
            stage.setFrames(top: top, bottom: bottomFrame, topRadius: 28, bottomRadius: 30,
                            animated: false, duration: 0, curve: .linear)
            stage.view.layoutIfNeeded()
        }
        layout(bottom)
        let topHost = UIView(), bottomHost = UIView()
        stage.topPane.install(topHost)
        stage.bottomPane.install(bottomHost)
        let topMask = stage.topPane.layer.mask, bottomMask = stage.bottomPane.layer.mask
        guard let chrome = stage.view.subviews.compactMap({ $0 as? DXStageChrome }).first,
              let preparation = stage.view.subviews.compactMap({ $0 as? DXStagePreparationView }).first else {
            check(false, "missing production chrome/preparation objects")
            return (count, failures)
        }
        chrome.layoutIfNeeded()
        check(!chrome.isHidden && chrome.frame.height == 44, "reserved 56pt gap did not display toolbar")
        check(chrome.frame.minY >= top.maxY && chrome.frame.maxY <= bottom.minY,
              "toolbar is not entirely inside the actual gap")
        check(!chrome.frame.intersects(top) && !chrome.frame.intersects(bottom), "toolbar overlaps app content")
        check(stage.view.hitTest(CGPoint(x: top.midX, y: top.midY), with: nil) === topHost,
              "ready top host does not receive local UIKit hits")
        var selected = false
        stage.showPicker(applications: [], excluding: nil) { _ in selected = true }
        check(stage.hasApplicationPicker, "ready picker was not attached")
        var closes = 0, chooses = 0, collapses = 0, switches = 0, focuses = 0
        var awaitingAcknowledgement = true
        stage.onClose = {
            closes += 1
            check(awaitingAcknowledgement, "close check did not execute while acknowledgement was pending")
        }
        stage.onChooseApplication = { chooses += 1 }
        stage.onCollapse = { collapses += 1 }
        stage.onSwitchInput = { switches += 1 }
        stage.onFocus = { _ in focuses += 1 }
        stage.setPreparing(true, message: "正在等待系统交互确认")
        check(stage.isPreparing && !preparation.isHidden, "preparation was not visible")
        check(preparation.activity.isAnimating, "preparation activity indicator is not running")
        check(preparation.messageLabel.text == "正在等待系统交互确认", "progress message is missing")
        check(!stage.hasApplicationPicker && stage.children.isEmpty && !selected,
              "preparation retained/fabricated a picker or selection")
        check(bottom.contains(preparation.frame), "initial progress card escaped the lower pane region")
        check(preparation.frame.width < stage.view.bounds.width,
              "preparation is a full-screen event-catching backdrop")
        check(window.isUserInteractionEnabled && stage.view.isUserInteractionEnabled &&
              stage.topPane.isUserInteractionEnabled && stage.bottomPane.isUserInteractionEnabled,
              "preparation globally disabled UIKit/window interaction")
        check(!stage.topPane.acceptsHostedTouches && !stage.bottomPane.acceptsHostedTouches,
              "preparation accepts hosted pane hits")
        check(stage.topPane.accessibilityElementsHidden && stage.bottomPane.accessibilityElementsHidden,
              "unready app accessibility remained exposed")
        check(stage.view.hitTest(CGPoint(x: top.midX, y: top.midY), with: nil) == nil,
              "preparing top pane still returns a local host hit")
        let outside = CGPoint(x: safe.minX + 2, y: top.maxY + 28)
        check(stage.view.hitTest(outside, with: nil) == nil, "preparation swallowed a point outside panes/chrome")
        for button in [chrome.chooseButton, chrome.collapseButton, chrome.switchInputButton] {
            check(button.isHidden && !button.isEnabled, "unavailable intent is visible/enabled during preparation")
            button.sendActions(for: .touchUpInside)
        }
        stage.topPane.onInteraction?()
        stage.showPicker(applications: [], excluding: nil) { _ in selected = true }
        check(!stage.hasApplicationPicker && chooses == 0 && collapses == 0 && switches == 0 && focuses == 0,
              "a forbidden preparing intent escaped its production guard")
        chrome.layoutIfNeeded()
        check(chrome.closeButton.isEnabled && !chrome.closeButton.isHidden, "close control was disabled")
        chrome.closeButton.sendActions(for: .touchUpInside)
        check(closes == 1, "toolbar close did not execute before acknowledgement")
        preparation.layoutIfNeeded()
        let cancelCenter = CGPoint(x: preparation.cancelButton.bounds.midX, y: preparation.cancelButton.bounds.midY)
        let cancelPoint = preparation.cancelButton.convert(cancelCenter, to: stage.view)
        check(stage.view.hitTest(cancelPoint, with: nil) === preparation.cancelButton,
              "preparation cancel is not reachable through the real root hit test")
        preparation.cancelButton.sendActions(for: .touchUpInside)
        check(closes == 2, "preparation cancel did not execute before acknowledgement")
        check(stage.accessibilityPerformEscape() && closes == 3, "accessibility escape did not cancel preparation")
        check(stage.isPreparing, "close UI falsely claimed native cleanup/acknowledgement finished")
        stage.setPreparationMessage("正在恢复系统场景")
        check(preparation.messageLabel.text == "正在恢复系统场景" && preparation.activity.isAnimating,
              "progress update lost the active preparation state")
        layout(bottom.offsetBy(dx: 0, dy: 8))
        check(!stage.topPane.acceptsHostedTouches && !stage.bottomPane.acceptsHostedTouches,
              "layout accidentally re-enabled unacknowledged hosted touches")
        let focused = CGRect(x: top.minX, y: safe.minY + 52, width: top.width, height: 320)
        stage.setInputFocused(.bottom, frame: focused, animated: false, duration: 0, curve: .linear)
        check(!stage.topPane.acceptsHostedTouches && !stage.bottomPane.acceptsHostedTouches,
              "input layout accidentally enabled hosted touches during preparation")
        check(chrome.frame.minY >= safe.minY && chrome.frame.maxY <= focused.minY - 8,
              "input toolbar overlaps focused app or safe-area header")
        awaitingAcknowledgement = false // Test admission flag only, not a bridge readiness fixture.
        stage.setPreparing(false, message: "")
        check(!stage.isPreparing && preparation.isHidden && !preparation.activity.isAnimating,
              "ready transition left stale progress/activity")
        check(!stage.topPane.acceptsHostedTouches && stage.bottomPane.acceptsHostedTouches,
              "ready input mode did not restore only the focused pane")
        check(stage.topPane.accessibilityElementsHidden && !stage.bottomPane.accessibilityElementsHidden,
              "ready input accessibility disagrees with pane visibility")
        check(chrome.chooseButton.isEnabled && chrome.collapseButton.isEnabled &&
              chrome.switchInputButton.isEnabled && !chrome.chooseButton.isHidden,
              "ready input-mode toolbar intents were not restored")
        stage.setInputFocused(nil, frame: nil, animated: false, duration: 0, curve: .linear)
        check(stage.topPane.acceptsHostedTouches && stage.bottomPane.acceptsHostedTouches,
              "ready split did not restore both pane hit regions")
        check(!chrome.switchInputButton.isEnabled, "switch input became enabled outside input mode")
        check(stage.topPane.layer.mask === topMask && stage.bottomPane.layer.mask === bottomMask &&
              stage.topPane.layer.cornerCurve == .continuous && stage.bottomPane.layer.cornerCurve == .continuous,
              "preparation replaced the continuously rounded pane masks")
        check(stage.topPane.hostedView === topHost && stage.bottomPane.hostedView === bottomHost,
              "preparation detached/replaced actual hosted view instances")
        layout(CGRect(x: bottom.minX, y: top.maxY + 12, width: bottom.width, height: bottom.height))
        check(chrome.frame == .zero && chrome.isHidden && !chrome.isUserInteractionEnabled,
              "insufficient gap fell back over an app's bottom navigation")
        stage.setInputFocused(.top, frame: CGRect(x: top.minX, y: safe.minY + 20,
                                                width: top.width, height: 320),
                              animated: false, duration: 0, curve: .linear)
        check(chrome.frame == .zero && chrome.isHidden, "missing input header fell back inside focused app")
        stage.setInputFocused(nil, frame: nil, animated: false, duration: 0, curve: .linear)
        layout(bottom)
        for _ in 0..<100 {
            stage.setPreparing(true, message: "")
            stage.setPreparing(false, message: "")
        }
        check(stage.view.subviews.filter { $0 is DXStagePreparationView }.count == 1 && stage.children.isEmpty,
              "repeated preparation accumulated progress views/pickers")
        stage.setPreparationMessage("stale progress")
        check(preparation.isHidden && preparation.messageLabel.text == nil,
              "stale progress update resurrected completed preparation")
        let unattached = DXStageViewController()
        unattached.setPreparing(true, message: " ")
        unattached.view.frame = window.bounds
        unattached.view.layoutIfNeeded()
        check(unattached.isPreparing && !unattached.hasApplicationPicker &&
              !unattached.topPane.acceptsHostedTouches && !unattached.bottomPane.acceptsHostedTouches,
              "pre-frame acquisition did not support explicit preparation")
        let noFramesProgress = unattached.view.subviews.compactMap { $0 as? DXStagePreparationView }.first
        check(noFramesProgress?.messageLabel.text?.isEmpty == false,
              "empty preparation text did not receive an explicit default message")
        let key = window.isKeyWindow
        let overlay = DXOverlayWindow(frame: window.bounds)
        let inactive = DXStageViewController()
        overlay.rootViewController = inactive
        overlay.isContextEnabled = false
        inactive.setPreparing(true, message: "pending")
        check(!overlay.isContextEnabled && overlay.isUserInteractionEnabled && !overlay.canBecomeKey &&
              window.isKeyWindow == key, "preparation stole key focus or overrode disabled system context")
        check(!inactive.accessibilityPerformEscape(), "disabled context delivered close intent")
        geometryChecks(check)
        return (count, failures)
    }

    private static func geometryChecks(_ check: (Bool, String) -> Void) {
        let safe = CGRect(x: 10, y: 47, width: 370, height: 700)
        let top = CGRect(x: 18, y: 55, width: 354, height: 280)
        let bottom = CGRect(x: 18, y: top.maxY + 56, width: 354, height: 280)
        func chrome(_ bottomFrame: CGRect, _ focused: CGRect? = nil, _ safeFrame: CGRect? = nil) -> CGRect {
            return DXStageChromeLayout.frame(safe: safeFrame ?? safe, top: top,
                                            bottom: bottomFrame, focused: focused)
        }
        let reserved = chrome(bottom)
        check(reserved.height == 44 && reserved.minY == top.maxY + 6 && reserved.maxY == bottom.minY - 6,
              "56pt reservation did not preserve both 6pt app clearances")
        for gap in [CGFloat(0), 12, 43, -20] {
            check(chrome(CGRect(x: 18, y: top.maxY + gap, width: 354, height: 280)) == .zero,
                  "unsafe split gap accepted: \(gap)")
        }
        let header = CGRect(x: 18, y: safe.minY + 52, width: 354, height: 400)
        let input = chrome(bottom, header)
        check(input.minY == safe.minY && input.height == 44 && input.maxY == header.minY - 8,
              "52pt reserved header was not used exactly")
        check(chrome(bottom, header.offsetBy(dx: 0, dy: -1)) == .zero, "51pt input header accepted")
        check(chrome(bottom, nil, CGRect(x: 0, y: 0, width: 180, height: 800)) == .zero,
              "narrow safe area compressed four controls below 44pt targets")
        check(chrome(bottom, .null) == .zero, "invalid focused frame accepted")
        check(chrome(bottom, nil, CGRect(x: 0, y: 0, width: 390, height: 320)) == .zero,
              "off-screen split gap was clamped over app content")
    }
}
