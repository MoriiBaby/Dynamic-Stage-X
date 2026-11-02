# Dynamic Stage X — local source implementation

- Product: Dynamic Stage X; package ID: com.tsangbaby.dynamicstagex.
- Current scope (2026-11-02 user testing feedback): fix Preferences-page crash and rebuild the native RootHide test package on `fix/preferences-alpha2`. Preserve main, original source snapshot and alpha1 branch. No merge, Release, device connection/attach, user-device install or respring. An ephemeral cloud iOS Simulator may run isolated UIKit regression tests; its Preferences superclass is a test double and is not device verification.
- Target: iOS 15.0+, no maximum-version gate. Swift-first, UIKit/CoreAnimation, minimal ObjC/C private-API bridge.
- Independent code: do not translate the reference binary, copy its resources/classes, or use its package as a dependency.
- Private calls require exact runtime ABI checks. Missing capabilities must produce explicit failure and retain native behavior. A view that only displays pixels is not a complete interactive scene.
- Prefer small files. Never report stub/snapshot/fake providers as working app hosting. Separate source completeness from compilation and device verification.
- Tests must exercise production policy where possible; source scans do not prove native behavior.
- Agents edit only assigned modules. Shared contracts are in Docs/CONTRACT.md; coordinate changes there with parent.
