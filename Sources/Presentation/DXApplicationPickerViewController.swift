import UIKit

private final class DXPickerEntry: NSObject {
    let record: DXApplicationRecord
    @objc var collationName: String {
        return record.displayName.isEmpty ? record.bundleIdentifier : record.displayName
    }
    init(record: DXApplicationRecord) { self.record = record; super.init() }
}

/// Real bridge records only. No local text responder, key-window request, or launch.
/// The default list is localized/indexed; trusted callers may filter without a keyboard.
internal final class DXApplicationPickerViewController: UIViewController,
    UITableViewDataSource, UITableViewDelegate {
    private let applications: [DXPickerEntry]
    private let collation = UILocalizedIndexedCollation.current()
    private var sections: [[DXPickerEntry]] = []
    private var resultCount = 0
    private let selection: (String) -> Void
    private let cancellation: () -> Void
    private var completed = false
    private let backdrop = UIControl()
    private let sheet = UIView()
    private let navigationBar = UINavigationBar()
    private let table = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()

    init(applications: [DXApplicationRecord], excluding: String?,
         selection: @escaping (String) -> Void, cancellation: @escaping () -> Void) {
        var seen = Set<String>()
        self.applications = applications.filter { record in
            let identifier = record.bundleIdentifier
            return !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                identifier != excluding && seen.insert(identifier).inserted
        }.map { DXPickerEntry(record: $0) }
        self.selection = selection
        self.cancellation = cancellation
        super.init(nibName: nil, bundle: nil)
        rebuildSections(query: "")
    }
    required init?(coder: NSCoder) { return nil }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        backdrop.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        backdrop.isAccessibilityElement = false
        view.addSubview(backdrop)
        sheet.backgroundColor = .secondarySystemBackground
        sheet.layer.cornerRadius = 20
        sheet.layer.cornerCurve = .continuous
        sheet.clipsToBounds = true
        sheet.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sheet)
        let safe = view.safeAreaLayoutGuide
        let preferredWidth = sheet.widthAnchor.constraint(equalTo: safe.widthAnchor, constant: -24)
        preferredWidth.priority = .defaultHigh
        let widthLimit = sheet.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, constant: -24)
        widthLimit.priority = UILayoutPriority(999)
        let preferredHeight = sheet.heightAnchor.constraint(equalToConstant: 600)
        preferredHeight.priority = .defaultHigh
        let bottom = sheet.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12)
        bottom.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            sheet.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            sheet.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            sheet.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            sheet.widthAnchor.constraint(lessThanOrEqualToConstant: 600),
            sheet.heightAnchor.constraint(lessThanOrEqualToConstant: 600),
            sheet.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 12),
            widthLimit, preferredWidth, preferredHeight, bottom
        ])
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        let item = UINavigationItem(title: "选择下方应用")
        item.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                target: self, action: #selector(cancel))
        navigationBar.setItems([item], animated: false)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 62
        table.sectionHeaderTopPadding = 0
        table.accessibilityIdentifier = "DX.applicationPicker.list"
        table.accessibilityHint = "应用按名称排序，可使用字母索引跳转；此处不会弹出键盘"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.isAccessibilityElement = true
        sheet.addSubview(navigationBar)
        sheet.addSubview(table)
        refreshEmptyState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        let width = sheet.bounds.width, height = sheet.bounds.height
        navigationBar.frame = CGRect(x: 0, y: 0, width: width, height: min(44, height))
        table.frame = CGRect(x: 0, y: navigationBar.frame.maxY, width: width,
                             height: max(0, height - navigationBar.frame.maxY))
    }

    /// A non-keyboard filter, e.g. an already-authorized external selection query.
    func filterApplications(query: String) {
        precondition(Thread.isMainThread)
        guard !completed else { return }
        rebuildSections(query: query)
        if isViewLoaded { table.reloadData(); refreshEmptyState() }
    }

    private func rebuildSections(query: String) {
        sections = Array(repeating: [], count: collation.sectionTitles.count)
        resultCount = 0
        for entry in applications where DXApplicationSearch.matches(query: query,
            name: entry.record.displayName, bundleIdentifier: entry.record.bundleIdentifier) {
            let section = collation.section(for: entry, collationStringSelector: #selector(getter: DXPickerEntry.collationName))
            guard sections.indices.contains(section) else { continue }
            sections[section].append(entry)
            resultCount += 1
        }
        for section in sections.indices {
            sections[section].sort {
                let comparison = $0.collationName.localizedStandardCompare($1.collationName)
                return comparison == .orderedSame ?
                    $0.record.bundleIdentifier < $1.record.bundleIdentifier : comparison == .orderedAscending
            }
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int { return sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections.indices.contains(section) ? sections[section].count : 0
    }
    func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return resultCount == 0 ? nil : collation.sectionIndexTitles
    }
    func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        guard collation.sectionIndexTitles.indices.contains(index) else { return 0 }
        return collation.section(forSectionIndexTitle: index)
    }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard sections.indices.contains(section), !sections[section].isEmpty else { return nil }
        return collation.sectionTitles[section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DX.application") ??
            UITableViewCell(style: .subtitle, reuseIdentifier: "DX.application")
        let entry = sections[indexPath.section][indexPath.row], record = entry.record
        var content = UIListContentConfiguration.subtitleCell()
        content.text = entry.collationName
        content.secondaryText = record.bundleIdentifier
        content.image = record.icon ?? UIImage(systemName: "app")
        content.imageProperties.maximumSize = CGSize(width: 32, height: 32)
        content.imageProperties.cornerRadius = 7
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "DX.application." + record.bundleIdentifier
        cell.accessibilityLabel = entry.collationName + "，" + record.bundleIdentifier
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !completed, sections.indices.contains(indexPath.section),
              sections[indexPath.section].indices.contains(indexPath.row) else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        completed = true
        selection(sections[indexPath.section][indexPath.row].record.bundleIdentifier)
    }

    private func refreshEmptyState() {
        emptyLabel.text = applications.isEmpty ? "没有可选择的应用" : "没有匹配应用"
        table.backgroundView = resultCount == 0 ? emptyLabel : nil
    }
    @objc private func cancel() {
        guard !completed else { return }
        completed = true
        cancellation()
    }
    func invalidate() { completed = true }
    override func accessibilityPerformEscape() -> Bool { cancel(); return true }
}
