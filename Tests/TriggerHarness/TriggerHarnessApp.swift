import UIKit

/// This is an ordinary foreground app scene, NOT SpringBoard or the production scene bridge.
@main
final class TriggerHarnessApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "TriggerHarness", sessionRole: session.role)
        configuration.delegateClass = TriggerHarnessScene.self
        return configuration
    }
}

final class TriggerHarnessScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var edge: DXEdgeTriggerWindow?
    private var dashboard: TriggerDashboard?
    private var sideTimer: Timer?
    private var sameSideWrites = 0
    private var triggerCount = 0
    private var side = "right"

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let arguments = ProcessInfo.processInfo.arguments
        side = arguments.contains("--left") ? "left" : "right"
        let dashboard = TriggerDashboard()
        let background = UIWindow(windowScene: scene)
        background.rootViewController = dashboard
        background.makeKeyAndVisible()
        window = background
        self.dashboard = dashboard

        // Compile and instantiate the unmodified production window, not a gesture double.
        let edge = DXEdgeTriggerWindow(windowScene: scene)
        edge.frame = scene.coordinateSpace.bounds
        edge.windowLevel = background.windowLevel + 1
        edge.triggerSide = side
        edge.isContextEnabled = !arguments.contains("--disabled")
        edge.onTrigger = { [weak self] in
            guard let self = self else { return }
            self.triggerCount += 1
            self.refresh()
        }
        self.edge = edge
        edge.isHidden = false // NEVER call makeKey()/makeKeyAndVisible() on the edge window.
        dashboard.onCheckpoint = { [weak self] in self?.refresh() }
        refresh()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if ProcessInfo.processInfo.arguments.contains("--repeat-side"), sideTimer == nil {
            // A real main-run-loop timer overlaps the XCUI touch stream. No recognizer mutation.
            let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
                guard let self = self, let edge = self.edge else { return }
                edge.triggerSide = self.side
                self.sameSideWrites += 1
            }
            RunLoop.main.add(timer, forMode: .common)
            sideTimer = timer
        }
        refresh()
    }

    func sceneWillResignActive(_ scene: UIScene) { refresh() }
    func sceneDidDisconnect(_ scene: UIScene) { sideTimer?.invalidate(); sideTimer = nil }

    private func refresh() {
        guard let window = window, let edge = edge, let dashboard = dashboard else { return }
        let foreground = window.windowScene?.activationState == .foregroundActive
        let nonKey = window.isKeyWindow && !edge.isKeyWindow && !edge.canBecomeKey
        let layered = edge.windowScene === window.windowScene && edge.windowLevel > window.windowLevel
        let ready = foreground && nonKey && layered && !edge.isHidden
        let values = ["ready": ready ? "1" : "0", "foreground": foreground ? "1" : "0",
                      "nonKey": nonKey ? "1" : "0", "layered": layered ? "1" : "0",
                      "triggers": String(triggerCount), "side": side,
                      "enabled": edge.isContextEnabled ? "1" : "0",
                      "sameSideWrites": String(sameSideWrites),
                      "outsidePans": String(dashboard.outsidePans),
                      "buttonTaps": String(dashboard.buttonTaps)]
        dashboard.show(values)
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys, .prettyPrinted]),
           let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? data.write(to: documents.appendingPathComponent("trigger-state.json"), options: .atomic)
        }
    }
}

final class TriggerDashboard: UIViewController {
    var onCheckpoint: (() -> Void)?
    private(set) var outsidePans = 0
    private(set) var buttonTaps = 0
    private var labels: [String: UILabel] = [:]
    private let keys = ["ready", "foreground", "nonKey", "layered", "triggers", "side",
                        "enabled", "sameSideWrites", "outsidePans", "buttonTaps"]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let title = UILabel()
        title.text = "Dynamic Stage X · real UIKit trigger"
        title.font = .boldSystemFont(ofSize: 15)
        stack.addArrangedSubview(title)
        for key in keys {
            let row = UIStackView()
            row.distribution = .fillEqually
            let name = UILabel()
            name.text = key
            let value = UILabel()
            value.text = "0"
            value.accessibilityIdentifier = "Harness." + key
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            labels[key] = value
            row.addArrangedSubview(name)
            row.addArrangedSubview(value)
            stack.addArrangedSubview(row)
        }
        let probe = UIButton(type: .system)
        probe.setTitle("Background button", for: .normal)
        probe.accessibilityIdentifier = "Harness.backgroundButton"
        probe.addTarget(self, action: #selector(tapBackground), for: .touchUpInside)
        stack.addArrangedSubview(probe)
        let checkpoint = UIButton(type: .system)
        checkpoint.setTitle("Checkpoint counters", for: .normal)
        checkpoint.accessibilityIdentifier = "Harness.checkpoint"
        checkpoint.addTarget(self, action: #selector(checkpointNow), for: .touchUpInside)
        stack.addArrangedSubview(checkpoint)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 25),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -25)
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(backgroundPan(_:)))
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
    }

    func show(_ values: [String: String]) {
        loadViewIfNeeded()
        for (key, value) in values { labels[key]?.text = value }
    }
    @objc private func tapBackground() { buttonTaps += 1; onCheckpoint?() }
    @objc private func checkpointNow() { onCheckpoint?() }
    @objc private func backgroundPan(_ recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .ended { outsidePans += 1; onCheckpoint?() }
    }
}
