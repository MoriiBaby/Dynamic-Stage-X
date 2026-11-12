import UIKit

@UIApplicationMain
final class DXStageAlpha4SmokeApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "StageSmoke", sessionRole: session.role)
        configuration.delegateClass = DXStageAlpha4SmokeScene.self
        return configuration
    }
}

final class DXStageAlpha4SmokeScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var started = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = DXStageViewController()
        self.window = window
        window.makeKeyAndVisible() // Simulator TEST app only, never the production overlay.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard !started, let window = window else { return }
        started = true
        DispatchQueue.main.async { self.exercise(in: window) }
    }

    private func exercise(in window: UIWindow) {
        let result = DXStageAlpha4Checks.run(in: window)
        let report: [String: Any] = [
            "passed": result.failures.isEmpty, "checks": result.checks, "failures": result.failures,
            "scope": "production stage/pane/chrome/picker/overlay UIKit; display record fixture only",
            "native_scene_hosting_tested": false, "native_event_acknowledgement_tested": false,
            "system_bridge_linked": false, "xcui_touch_injection_tested": false,
            "preferences_tested": false, "physical_device_actions": false
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("result.json")
            try data.write(to: url, options: .atomic)
            print(String(decoding: data, as: UTF8.self))
        } catch { print("Stage alpha4 smoke result write failed: \(error)"); exit(2) }
        exit(result.failures.isEmpty ? 0 : 1)
    }
}
