import UIKit
import CoreFoundation

/// Preferences navigation container. It deliberately has no table delegate/data-source methods.
@objc(DXPreferencesController)
public final class DXPreferencesController: PSViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Dynamic Stage X"
        view.backgroundColor = .systemGroupedBackground
        let contents = DXSettingsListController(style: .insetGrouped)
        addChild(contents)
        let contentView = contents.view!
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        contents.didMove(toParent: self)
    }
}

/// Owns one UIKit table; never supplies callbacks to PSListController's specifier table.
private final class DXSettingsListController: UITableViewController {
    private let domain = "com.tsangbaby.dynamicstagex" as CFString
    private var table: UITableView { tableView }
    private let keys = ["enabled", "cornerRadius", "gap", "triggerSide"]
    private let titles = ["启用 Dynamic Stage X", "窗口圆角", "窗口间隔", "触发位置"]

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        CFPreferencesAppSynchronize(domain)
        table.reloadData()
    }
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? keys.count : 1 }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? "竖屏上下双窗。键盘出现时输入应用临时占据键盘上方区域，收起键盘后恢复。系统目标 iOS 15.0+，具体能力以运行时适配与验证为准。" : "开发者 Tsangbaby · 0.1.0-alpha2\n此设置不会安装、重启或强制关闭任何应用。"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        guard indexPath.section == 0 else {
            cell.textLabel?.text = "关于 Dynamic Stage X"
            cell.detailTextLabel?.text = "Swift · iOS 15.0+"
            cell.selectionStyle = .none
            return cell
        }
        let row = indexPath.row
        cell.textLabel?.text = titles[row]
        switch row {
        case 0:
            let toggle = UISwitch()
            toggle.isOn = (read(keys[row]) as? NSNumber)?.boolValue ?? false
            toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
            toggle.accessibilityLabel = titles[row]
            cell.accessoryView = toggle
            cell.selectionStyle = .none
        case 1, 2:
            let value = (read(keys[row]) as? NSNumber)?.doubleValue ?? (row == 1 ? 28 : 6)
            cell.detailTextLabel?.text = "\(Int(value)) pt"
            cell.accessoryType = .disclosureIndicator
        default:
            cell.detailTextLabel?.text = (read("triggerSide") as? String) == "left" ? "左下角" : "右下角"
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 0, indexPath.row > 0 else { return }
        if indexPath.row == 3 {
            let alert = UIAlertController(title: "触发位置", message: nil, preferredStyle: .actionSheet)
            for (name, value) in [("左下角", "left"), ("右下角", "right")] {
                alert.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in self?.write(value, key: "triggerSide") })
            }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.popoverPresentationController?.sourceView = tableView.cellForRow(at: indexPath)
            present(alert, animated: true)
        } else {
            let row = indexPath.row
            let range = row == 1 ? 12...44 : 2...16
            let value = (read(keys[row]) as? NSNumber)?.intValue ?? (row == 1 ? 28 : 6)
            let alert = UIAlertController(title: titles[row], message: "输入 \(range.lowerBound)–\(range.upperBound) pt", preferredStyle: .alert)
            alert.addTextField { field in field.keyboardType = .numberPad; field.text = String(value) }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
                guard let self = self, let text = alert?.textFields?.first?.text,
                      let number = Int(text), range.contains(number) else { return }
                self.write(number, key: self.keys[row])
            })
            present(alert, animated: true)
        }
    }
    @objc private func toggleChanged(_ sender: UISwitch) { write(sender.isOn, key: "enabled") }
    private func read(_ key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain) }
    private func write(_ value: Any, key: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList, domain)
        CFPreferencesAppSynchronize(domain)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: "com.tsangbaby.dynamicstagex/preferences-changed" as CFString), nil, nil, true)
        table.reloadData()
    }
}
