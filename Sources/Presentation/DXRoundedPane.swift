import UIKit

/// A passive recognizer: it fails rather than recognizes, never delays or cancels
/// touches, and cannot prevent (or be prevented by) the hosted app's recognizers.
internal final class DXInteractionObserver: UIGestureRecognizer {
    var observed: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        observed?()
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { return false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { return false }
}

final class DXRoundedPane: UIView {
    var onInteraction: (() -> Void)?
    private(set) var hostedView: UIView?
    internal var acceptsHostedTouches = true

    var radius: CGFloat {
        get { return requestedRadius }
        set {
            precondition(Thread.isMainThread)
            requestedRadius = newValue.isFinite ? max(0, newValue) : 0
            updateMask(from: nil, duration: 0, curve: .linear)
        }
    }

    private struct HostLayout {
        let bounds: CGRect
        let center: CGPoint
        let autoresizingMask: UIView.AutoresizingMask
        let translatesAutoresizingMaskIntoConstraints: Bool
    }
    internal struct Presentation {
        let frame: CGRect
        let radius: CGFloat
        let alpha: CGFloat
        let path: CGPath
    }

    private var originalLayout: HostLayout?
    private let clippingMask = CAShapeLayer()
    private var requestedRadius: CGFloat = 28
    private var maskUpdatesSuspended = false
    private var lastMaskSize: CGSize?
    private var lastMaskOrigin: CGPoint?
    private var lastMaskRadius: CGFloat?
    private var interactionGeneration: UInt64 = 0
    private static let maskAnimationKey = "DX.cornerPath"

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .clear
        clipsToBounds = true
        // The explicit C2-continuous mask is authoritative for both rendering and
        // hit testing. Do not additionally clip using Apple's undocumented path.
        layer.cornerCurve = .continuous
        layer.cornerRadius = 0
        clippingMask.fillColor = UIColor.black.cgColor
        clippingMask.anchorPoint = .zero
        layer.mask = clippingMask
        isAccessibilityElement = false // Preserve the actual host's AX hierarchy.
        let observer = DXInteractionObserver(target: nil, action: nil)
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.observed = { [weak self] in self?.observeInteraction() }
        addGestureRecognizer(observer)
        updateMask(from: nil, duration: 0, curve: .linear)
    }

    func install(_ hostedView: UIView) {
        precondition(Thread.isMainThread)
        guard hostedView !== self, !isDescendant(of: hostedView) else {
            assertionFailure("A pane cannot host itself or an ancestor")
            return
        }
        if self.hostedView === hostedView, hostedView.superview === self {
            setNeedsLayout()
            layoutIfNeeded()
            return
        }
        if let previousPane = hostedView.superview as? DXRoundedPane, previousPane !== self {
            previousPane.detach()
        }
        detach()
        originalLayout = HostLayout(bounds: hostedView.bounds, center: hostedView.center,
                                    autoresizingMask: hostedView.autoresizingMask,
                                    translatesAutoresizingMaskIntoConstraints:
                                        hostedView.translatesAutoresizingMaskIntoConstraints)
        // Bridge supplies a dedicated real, untransformed host, not a snapshot.
        hostedView.removeFromSuperview()
        hostedView.translatesAutoresizingMaskIntoConstraints = true
        hostedView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.hostedView = hostedView
        addSubview(hostedView)
        setNeedsLayout()
        layoutIfNeeded()
    }

    func detach() {
        precondition(Thread.isMainThread)
        interactionGeneration &+= 1
        if let host = hostedView, host.superview === self {
            host.removeFromSuperview()
            if let saved = originalLayout {
                host.autoresizingMask = saved.autoresizingMask
                host.translatesAutoresizingMaskIntoConstraints = saved.translatesAutoresizingMaskIntoConstraints
                host.bounds = saved.bounds
                host.center = saved.center
            }
        }
        // If another owner already reparented the view, do not alter its state.
        hostedView = nil
        originalLayout = nil
    }

    deinit {
        // Contract confines this view and its owner to the main thread.
        if Thread.isMainThread { detach() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let host = hostedView, host.superview === self {
            let origin = originalLayout?.bounds.origin ?? .zero
            host.bounds = CGRect(origin: origin, size: bounds.size)
            host.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        if !maskUpdatesSuspended,
           lastMaskSize != bounds.size || lastMaskOrigin != bounds.origin || lastMaskRadius != requestedRadius {
            updateMask(from: nil, duration: 0, curve: .linear)
        }
    }

    internal func cancelPendingInteraction() { interactionGeneration &+= 1 }

    private func observeInteraction() {
        let generation = interactionGeneration
        // Do not let a focus request mutate the hierarchy in touchesBegan.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.interactionGeneration == generation,
                  self.acceptsHostedTouches, !self.isHidden, self.alpha > 0.01,
                  let host = self.hostedView, host.superview === self,
                  let window = self.window, !window.isHidden else { return }
            if let scene = window.windowScene, scene.activationState != .foregroundActive { return }
            self.onInteraction?()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard acceptsHostedTouches, point.x.isFinite, point.y.isFinite else { return false }
        let visible = layer.presentation() ?? layer
        let local = CGPoint(x: point.x - visible.bounds.minX, y: point.y - visible.bounds.minY)
        let path = (clippingMask.presentation() as? CAShapeLayer)?.path ?? clippingMask.path
        return path?.contains(local, using: .winding, transform: .identity) ?? false
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard hostedView?.superview === self else { return nil }
        return super.hitTest(point, with: event)
    }

    /// Stage root uses visible pane geometry while its frame is in flight.
    /// Native cross-process event-coordinate correctness still needs device tests.
    internal func hitTestFromParent(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard acceptsHostedTouches, !isHidden, isUserInteractionEnabled,
              hostedView?.superview === self else { return nil }
        let visible = layer.presentation() ?? layer
        guard visible.opacity > 0.01, visible.affineTransform().isIdentity,
              visible.bounds.width > 0, visible.bounds.height > 0 else { return nil }
        let origin = CGPoint(x: visible.position.x - visible.bounds.width * visible.anchorPoint.x,
                             y: visible.position.y - visible.bounds.height * visible.anchorPoint.y)
        let local = CGPoint(x: point.x - origin.x + visible.bounds.minX,
                            y: point.y - origin.y + visible.bounds.minY)
        guard self.point(inside: local, with: event) else { return nil }
        let modelPoint = CGPoint(
            x: bounds.minX + (local.x - visible.bounds.minX) * bounds.width / visible.bounds.width,
            y: bounds.minY + (local.y - visible.bounds.minY) * bounds.height / visible.bounds.height)
        for child in subviews.reversed() {
            if let hit = child.hitTest(child.convert(modelPoint, from: self), with: event) { return hit }
        }
        return self
    }

    internal func capturePresentation() -> Presentation {
        let visible = layer.presentation() ?? layer
        let path = (clippingMask.presentation() as? CAShapeLayer)?.path ??
            clippingMask.path ?? DXContinuousCornerPath.make(size: visible.bounds.size, radius: radius)
        return Presentation(frame: visible.frame, radius: DXContinuousCornerPath.sampledRadius(in: path),
                            alpha: CGFloat(visible.opacity), path: path)
    }

    internal func freeze(_ state: Presentation) {
        maskUpdatesSuspended = true
        frame = state.frame
        requestedRadius = state.radius
        alpha = state.alpha
        setNeedsLayout()
        layoutIfNeeded()
        maskUpdatesSuspended = false
        clippingMask.removeAnimation(forKey: Self.maskAnimationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clippingMask.bounds = CGRect(origin: .zero, size: bounds.size)
        clippingMask.position = bounds.origin
        clippingMask.path = state.path
        lastMaskSize = bounds.size
        lastMaskOrigin = bounds.origin
        lastMaskRadius = requestedRadius
        CATransaction.commit()
    }

    internal func apply(frame: CGRect, radius: CGFloat, alpha: CGFloat,
                        from path: CGPath, duration: TimeInterval, curve: UIView.AnimationCurve) {
        maskUpdatesSuspended = true
        self.frame = frame
        requestedRadius = radius
        self.alpha = alpha
        setNeedsLayout()
        layoutIfNeeded()
        maskUpdatesSuspended = false
        updateMask(from: path, duration: duration, curve: curve)
    }

    private func updateMask(from oldPath: CGPath?, duration: TimeInterval, curve: UIView.AnimationCurve) {
        let target = DXContinuousCornerPath.make(size: bounds.size, radius: requestedRadius)
        lastMaskSize = bounds.size
        lastMaskOrigin = bounds.origin
        lastMaskRadius = requestedRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clippingMask.bounds = CGRect(origin: .zero, size: bounds.size)
        clippingMask.position = bounds.origin
        clippingMask.path = target
        CATransaction.commit()
        clippingMask.removeAnimation(forKey: Self.maskAnimationKey)
        if duration > 0, let oldPath = oldPath {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = oldPath
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = DXUIGeometry.timing(curve)
            clippingMask.add(animation, forKey: Self.maskAnimationKey)
        }
    }
}
