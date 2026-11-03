import UIKit
import CoreFoundation

@UIApplicationMain
final class DXPreferencesSmokeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var failures: [String] = []
    private var checks = 0
    private var dataSourceType: String?
    private let domain = "com.tsangbaby.dynamicstagex" as CFString

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let baseline = ProcessInfo.processInfo.arguments.contains("--baseline")
        let root = DXPreferencesController()
        let exception = DXCaptureException { root.loadViewIfNeeded() }
        if baseline {
            check(exception == "NSRangeException", "baseline did not expose modeled PSList specifier collision")
            finish(baseline: true, exception: exception)
            return true
        }
        check(exception == nil, "fixed controller threw while loading: \(exception ?? "")")
        check(!root.isKind(of: PSListController.self), "fixed container still inherits PSListController")
        for selector in ["numberOfSectionsInTableView:", "tableView:numberOfRowsInSection:",
                         "tableView:cellForRowAtIndexPath:", "tableView:heightForHeaderInSection:"] {
            check(!root.responds(to: NSSelectorFromString(selector)), "container owns table selector \(selector)")
        }
        check(root.children.count == 1, "container does not own exactly one UIKit child")
        check(DXPreferencesParentLoads() > 0, "super.viewDidLoad was bypassed")
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UINavigationController(rootViewController: root)
        self.window = window
        window.makeKeyAndVisible() // Test host only; the remote-stage overlay is not linked here.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.exercise(root)
        }
        return true
    }

    private func exercise(_ root: DXPreferencesController) {
        guard let list = root.children.first as? UITableViewController else {
            check(false, "missing UIKit table controller"); finish(baseline: false, exception: nil); return
        }
        let table = list.tableView!
        let exception = DXCaptureException {
            root.view.layoutIfNeeded()
            for _ in 0..<10 { table.reloadData(); table.layoutIfNeeded() }
        }
        check(exception == nil, "real UIKit reload/layout threw: \(exception ?? "")")
        guard let dataSource = table.dataSource else {
            check(false, "UIKit table has no effective data source"); finish(baseline: false, exception: exception); return
        }
        // UITableViewController may install a UIKit forwarding data source. Test the
        // effective callback results, not an undocumented internal pointer identity.
        dataSourceType = String(describing: type(of: dataSource))
        check(dataSource.tableView(table, numberOfRowsInSection: 0) == 4,
              "effective data source does not route setting rows")
        check(dataSource.tableView(table, numberOfRowsInSection: 1) == 1,
              "effective data source does not route about rows")
        check(table.delegate === list, "child is not the table delegate")
        check(table.numberOfSections == 2, "wrong section count")
        check(table.numberOfRows(inSection: 0) == 4, "missing setting rows")
        check(table.numberOfRows(inSection: 1) == 1, "missing about row")
        let expected = ["启用 Dynamic Stage X", "窗口圆角", "窗口间隔", "触发位置"]
        for row in 0..<4 {
            let cell = dataSource.tableView(table, cellForRowAt: IndexPath(row: row, section: 0))
            check(cell.textLabel?.text == expected[row], "row title mismatch \(row)")
        }
        check(list.tableView(table, titleForFooterInSection: 1)?.contains("0.1.0-alpha3") == true,
              "about footer did not identify alpha3")
        let old = CFPreferencesCopyAppValue("enabled" as CFString, domain)
        let cell = dataSource.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0))
        if let toggle = cell.accessoryView as? UISwitch {
            toggle.setOn(true, animated: false)
            toggle.sendActions(for: .valueChanged)
            check((CFPreferencesCopyAppValue("enabled" as CFString, domain) as? NSNumber)?.boolValue == true,
                  "enable switch did not persist true")
            toggle.setOn(false, animated: false)
            toggle.sendActions(for: .valueChanged)
            check((CFPreferencesCopyAppValue("enabled" as CFString, domain) as? NSNumber)?.boolValue == false,
                  "enable switch did not persist false")
        } else { check(false, "missing enable switch") }
        // These writes are only inside this ephemeral simulator, never a user's Preferences process.
        CFPreferencesSetAppValue("enabled" as CFString, old, domain)
        CFPreferencesAppSynchronize(domain)
        list.tableView(table, didSelectRowAt: IndexPath(row: 1, section: 0))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self else { return }
            let alert = list.presentedViewController as? UIAlertController
            self.check(alert?.title == "窗口圆角", "radius editor was not presented")
            self.check(alert?.textFields?.count == 1 && alert?.actions.count == 2,
                       "radius editor controls mismatch")
            list.dismiss(animated: false) {
                list.tableView(table, didSelectRowAt: IndexPath(row: 3, section: 0))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    let choice = list.presentedViewController as? UIAlertController
                    self.check(choice?.title == "触发位置", "trigger choice was not presented")
                    self.check(choice?.actions.count == 3, "trigger choices mismatch")
                    self.finish(baseline: false, exception: exception)
                }
            }
        }
    }

    private func check(_ success: Bool, _ message: String) {
        checks += 1
        if !success { failures.append(message) }
    }
    private func finish(baseline: Bool, exception: String?) {
        let report: [String: Any] = [
            "passed": failures.isEmpty, "checks": checks, "failures": failures,
            "effective_data_source_class": (dataSourceType as Any?) ?? NSNull(),
            "baseline": baseline, "captured_exception": (exception as Any?) ?? NSNull(),
            "scope": "real iOS Simulator UIKit; Preferences superclass is a test double, not the real Preferences host",
            "device_settings_tested": false
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("result.json")
            try data.write(to: url, options: .atomic)
            print(String(decoding: data, as: UTF8.self))
        } catch { print("Smoke result write failed: \(error)"); exit(2) }
        exit(failures.isEmpty ? 0 : 1)
    }
}
