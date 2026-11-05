import UIKit

/// No opaque/full-screen catch-all view: a gap is genuinely pass-through.
internal final class DXStageRootView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled,
              self.point(inside: point, with: event) else { return nil }
        for child in subviews.reversed() {
            if let pane = child as? DXRoundedPane {
                if let hit = pane.hitTestFromParent(point, with: event) { return hit }
            } else if let hit = child.hitTest(child.convert(point, from: self), with: event) {
                return hit
            }
        }
        return nil
    }
}

internal final class DXStageChrome: UIView {
    let closeButton = UIButton(type: .system)
    let collapseButton = UIButton(type: .system)
    let chooseButton = UIButton(type: .system)
    let switchInputButton = UIButton(type: .system)
    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        addSubview(background)
        addSubview(stack)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        let items: [(UIButton, String, String, String)] = [
            (closeButton, "xmark", "关闭分屏", "DX.close"),
            (collapseButton, "chevron.down", "收起分屏", "DX.collapse"),
            (chooseButton, "plus.app", "选择下方应用", "DX.choose"),
            (switchInputButton, "arrow.up.arrow.down", "切换输入窗口", "DX.switchInput")
        ]
        for (button, symbol, label, identifier) in items {
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.accessibilityLabel = label
            button.accessibilityIdentifier = identifier
            button.tintColor = .label
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(button)
        }
        switchInputButton.accessibilityHint = "仅在键盘输入专注模式可用"
    }

    /// Preparation never disables the close control, only unavailable intents.
    func setPreparing(_ preparing: Bool, inputFocused: Bool) {
        closeButton.isEnabled = true
        closeButton.accessibilityLabel = preparing ? "取消准备并关闭分屏" : "关闭分屏"
        for button in [collapseButton, chooseButton, switchInputButton] {
            button.isHidden = preparing
            button.isEnabled = !preparing
        }
        switchInputButton.isEnabled = !preparing && inputFocused
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        stack.frame = bounds
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return UIBezierPath(roundedRect: bounds, cornerRadius: min(bounds.height, bounds.width) / 2)
            .contains(point)
    }
}

/// Uses only space actually reserved by the caller. Never falls back inside an app.
internal enum DXStageChromeLayout {
    static func frame(safe: CGRect, top: CGRect, bottom: CGRect, focused: CGRect?) -> CGRect {
        guard DXUIGeometry.valid(safe), DXUIGeometry.valid(top), DXUIGeometry.valid(bottom) else {
            return .zero
        }
        let width = min(224, max(0, safe.width - 16))
        guard width >= 176 else { return .zero }
        let y: CGFloat
        if let focused = focused {
            // Parent reserves 52pt ABOVE the native focused frame (44pt + 8pt).
            guard DXUIGeometry.valid(focused), focused.minY - safe.minY >= 52 else { return .zero }
            y = focused.minY - 52
        } else {
            let start = max(safe.minY, top.maxY)
            let end = min(safe.maxY, bottom.minY)
            guard end - start >= 44 else { return .zero }
            y = start + (end - start - 44) / 2
        }
        let frame = CGRect(x: safe.midX - width / 2, y: y, width: width, height: 44)
        guard safe.contains(frame) else { return .zero }
        if let focused = focused {
            return frame.intersects(focused) ? .zero : frame
        }
        return frame.intersects(top) || frame.intersects(bottom) ? .zero : frame
    }
}

/// Bounded progress UI, not an application, picker, backdrop, or event-ready claim.
internal final class DXStagePreparationView: UIView {
    let cancelButton = UIButton(type: .system)
    let activity = UIActivityIndicatorView(style: .medium)
    let messageLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        clipsToBounds = true
        accessibilityIdentifier = "DX.preparation"
        activity.accessibilityIdentifier = "DX.preparation.activity"
        activity.isAccessibilityElement = false
        messageLabel.font = .preferredFont(forTextStyle: .callout)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.textColor = .label
        messageLabel.accessibilityIdentifier = "DX.preparation.message"
        cancelButton.setTitle("取消并关闭分屏", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .callout)
        cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        cancelButton.accessibilityIdentifier = "DX.preparation.cancel"
        cancelButton.accessibilityHint = "立即请求关闭；系统场景恢复可能仍需等待"
        addSubview(activity)
        addSubview(messageLabel)
        addSubview(cancelButton)
        isHidden = true
    }

    required init?(coder: NSCoder) { return nil }

    func setPreparing(_ preparing: Bool, message: String) {
        isHidden = !preparing
        messageLabel.text = preparing ? message : nil
        if preparing { activity.startAnimating() } else { activity.stopAnimating() }
        cancelButton.isEnabled = true
        setNeedsLayout()
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let width = min(320, max(0, size.width))
        let text = messageLabel.sizeThatFits(CGSize(width: max(0, width - 64),
                                                    height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: min(size.height, max(144, ceil(text.height) + 88)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        activity.frame = CGRect(x: 16, y: 20, width: 20, height: 20)
        let buttonHeight = min(44, bounds.height)
        cancelButton.frame = CGRect(x: 12, y: max(0, bounds.height - 16 - buttonHeight),
                                    width: max(0, bounds.width - 24), height: buttonHeight)
        messageLabel.frame = CGRect(x: 48, y: 16, width: max(0, bounds.width - 64),
                                    height: max(0, cancelButton.frame.minY - 28))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return UIBezierPath(roundedRect: bounds, cornerRadius: 20).contains(point)
    }
}
