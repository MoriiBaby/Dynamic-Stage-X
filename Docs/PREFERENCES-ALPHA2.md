# Preferences crash fix — 0.1.0-alpha2

## Proven failure evidence

User reported Settings crashing on opening the Dynamic Stage X page. The local crash image UUID matched the delivered alpha1 arm64e Preferences bundle. The exception is SIGABRT after an Objective-C array-index exception, on the main thread. Key chain:

```text
DXPreferencesController.viewDidLoad
  → PSListController.viewDidLoad
  → UITableView.reloadData / section header layout
  → PSListController._tableView:heightForCustomInSection:isHeader:
  → NSMutableArray.objectAtIndex / exception
```

The initial Swift controller inherited `PSListController` but provided a separate UIKit table's section/row callbacks, including `numberOfSections=2`. Dynamic dispatch during `super.viewDidLoad` let the parent use those callbacks with its different specifier-group model. This is the high-confidence cause supported by the actual failure stack and source order; the report does not give the internal failing array index/count. VM shortage notes are present, but this stack identifies an uncaught table-model exception, not a jetsam or missing-dependency termination.

No raw crash log, device identifier, incident ID or RootHide mount path is placed in the repository. The user's original report stays local and unchanged.

## Minimal production repair

- Keep the public ObjC name, PreferenceLoader entry, package identity and preference domain.
- Use real Preferences `PSViewController` as navigation/container parent. Both Swift inheritance and compile-time bridge now agree.
- Only a private `UITableViewController` child owns section/data-source/delegate methods, and uses UIKit's one table.
- Parent lifecycle stays intact: super.viewDidLoad → construct child → addChild → attach child view/constraints → didMove.
- The four stored keys, defaults, switch callback, CFPreferences write and Darwin notification remain unchanged. Existing settings are not deleted or migrated.
- Mark the test candidate as `0.1.0~alpha2` / bundle version2, to distinguish the crashing alpha1.
- All `Sources/` files and the previous core/presentation tests are unchanged from alpha1; no split-window, keyboard, event or private-scene changes are included.

Fixed source API basis: RootHide headers pinned to `744ee65cd464becd8b06cab6eaeffc0512b371f1/Preferences/PSViewController.h` declare `PSViewController:UIViewController`. The RootHide PreferenceLoader detail contract accepts PSViewController subclasses. This is interface evidence, not a claim that a private framework is constant on future systems. iOS15.0+ target and no maximum OS gate are retained.

## Verification contract

Before delivery: source regression +35-file frozen source check, actual Mac Foundation Swift tests, production C tests, new Preferences simulator regression, dual arm64/arm64e native RootHide build, package metadata/owner/dependency/signature inspection, artifact digest and commit match. The simulator uses real UIKit but a test double for Preferences superclass, so a passed test does not alone certify the user's real Settings host. The old failure and post-fix UI runtime acceptance are separate evidence levels.

The cloud workflow only listens to `fix/preferences-alpha2`; main and alpha1 stay preserved. No merge, Release, phone connection/attach, install, respring or preference clearing is performed. Final run/artifact/check results are delivered separately after actual completion, not predeclared in this document.
