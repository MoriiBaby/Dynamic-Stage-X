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
