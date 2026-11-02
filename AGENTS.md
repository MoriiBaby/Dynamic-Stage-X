# Dynamic Stage X — local source implementation

- Product: Dynamic Stage X; package ID: com.tsangbaby.dynamicstagex.
- Current scope (2026-11-02 user authorization): cloud macOS native RootHide build and test-DEB delivery. Build fixes/CI commits are allowed on `build/roothide-alpha1`; preserve main and the original source snapshot. No merge, Release, device connection/attach, install, or respring.
- Target: iOS 15.0+, no maximum-version gate. Swift-first, UIKit/CoreAnimation, minimal ObjC/C private-API bridge.
- Independent code: do not translate the reference binary, copy its resources/classes, or use its package as a dependency.
- Private calls require exact runtime ABI checks. Missing capabilities must produce explicit failure and retain native behavior. A view that only displays pixels is not a complete interactive scene.
- Prefer small files. Never report stub/snapshot/fake providers as working app hosting. Separate source completeness from compilation and device verification.
- Tests must exercise production policy where possible; source scans do not prove native behavior.
- Agents edit only assigned modules. Shared contracts are in Docs/CONTRACT.md; coordinate changes there with parent.
