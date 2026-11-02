# Preferences alpha2 regression

The production `DXPreferencesController` is a Preferences `PSViewController` navigation container, not `PSListController`. Its private UIKit `UITableViewController` child exclusively owns section/row/delegate callbacks. This cuts the observed exception path without hiding it by skipping `super.viewDidLoad` or supplying fake specifiers.

## Tests

- `python3 Tests/Preferences/check_preferences_contract.py`: source structure, original preference keys/write/notification bytes, containment order, no main-source changes and test shim exclusion. It requires the alpha1 Git commit in local history. These are source contracts, not a runtime proof.
- `python3 ci/test_preferences_simulator.py`: cloud Mac only, real Apple simulator UIKit, compile the exact old/fixed Swift controller with a **test-only** Preferences superclass. A modeled PSList specifier/table ownership conflict must produce `NSRangeException` for the old source. The fixed source must load/layout/reload its UIKit child, retain two sections and four setting rows plus about, persist switch values, and show its editors. Baseline exception collection is test-only and is never linked into production.

The simulator test checks actual UIKit behavior and Swift/Objective-C calls. It does **not** run the real private `Preferences.framework` or the user's Preferences.app, and it does not validate all iOS versions or RootHide injection. The user's alpha1 crash UUID/call stack is the independent evidence for the real old failure. The isolated simulator writes only its own app container and is deleted after the test; no phone is connected or modified.

Current source build files include only `Preferences/DXPreferencesController.swift`. The shim, test app and scripts do not enter the RootHide DEB. Actual new-package verification must still check this and the imported PSViewController symbol.
