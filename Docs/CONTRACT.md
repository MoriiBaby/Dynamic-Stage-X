# Shared implementation contracts (v1)

Project: `/var/minis/workspace/dynamicstagex`. No remote writes or device actions. Swift 5 language mode/iOS15.0. Names prefixed DX in ObjC; Swift internal types use DX prefix too. No concurrency/async requirement: UI/coordination on main queue, cancellable callbacks. Source-only 0.1.0-alpha1.

## Core owned by core agent

Only `Sources/Core/` and `Tests/Core/`, plus `Package.swift` (host core package). Foundation-only, not UIKit. Expose these internal/public types usable from other Swift files:

- `DXRect` (Double x,y,width,height, init; finite validity and intersection), `DXInsets` (top,left,bottom,right Doubles), `DXSlot` enum top/bottom.
- `DXLayoutPolicy`: `static func split(bounds: DXRect, safeArea: DXInsets, ratio: Double, gap: Double, margin: Double, radius: Double) -> DXLayout?`; `DXLayout` contains `top,bottom:DXRect`, `topRadius,bottomRadius:Double`. Top/bottom content should fit safe-area usable space without compression; validate finite geometry.
- `DXKeyboardPolicy`: `static func focusedFrame(bounds:DXRect, safeArea:DXInsets, keyboard:DXRect, minimumHeight:Double) -> DXRect?`. Nil for invalid/too small; detect docked vs floating via helper; hardware zero height no full-screen promotion.
- `DXSessionToken` UUID based equatable; `DXPhase` idle/selecting/preparing/split/inputFocused/collapsed/dismissing; `DXStateMachine` mutating transitions beginSelection/prepare/splitReady/focus/collapse/resume/beginDismiss/finishDismiss (throw/Bool explicit); `generation`/token matching late completions. Exact API document in Core/API.md, parent may adapt callsites.
- Pure Swift lifetime cancellation/ownership helpers if useful; no fake scene provider.

## Bridge owned by system agent

Only `Sources/System/` (ObjC .h/.m, include own non-clashing .c helpers if needed), `Docs/SYSTEM-API.md`, `Tests/Bridge/`. Main umbrella `Sources/System/DXSystemBridge.h` imported by bridging header.

Provide public ObjC interfaces, Swift can consume directly:

`DXApplicationRecord` readonly `bundleIdentifier`, `displayName` NSString; nullable `icon` UIImage.
`DXSystemSceneHandle` readonly `bundleIdentifier`, `sceneIdentifier` NSString, `processIdentifier` pid_t, `hostView` UIView; readonly `valid` BOOL.
`DXSystemBridge`: `+sharedBridge` (Swift `DXSystemBridge.shared()` via NS_SWIFT_NAME if desired), instance methods:
- `-capabilityReport -> NSDictionary<NSString*, id>*` (metadata not runnable guarantee)
- `-frontmostApplicationIdentifier -> nullable NSString*`
- `-applications -> NSArray<DXApplicationRecord*>*`
- `-acquireSceneForBundleIdentifier:(NSString*)identifier completion:(void (^)(DXSystemSceneHandle * _Nullable, NSError * _Nullable))completion;` NS_SWIFT_NAME(acquireScene(bundleIdentifier:completion:))
- `-applyFrame:(CGRect)frame toHandle:(DXSystemSceneHandle*)handle completion:(void (^)(NSError * _Nullable))completion;` NS_SWIFT_NAME(apply(frame:to:completion:))
- `-focusHandle:(DXSystemSceneHandle*)handle completion:(void (^)(NSError * _Nullable))completion;` NS_SWIFT_NAME(focus(_:completion:))
- `-releaseHandle:(DXSystemSceneHandle*)handle completion:(void (^)(NSError * _Nullable))completion;` NS_SWIFT_NAME(release(_:completion:))
- `-activateNativeApplication:(NSString*)identifier completion:(void (^)(NSError * _Nullable))completion;` NS_SWIFT_NAME(activateNative(bundleIdentifier:completion:))
- `-keyboardFocusProcessIdentifier -> pid_t` (0 unknown)
- `-isLocked -> BOOL` fail closed if no lock capability

Validate exact method signatures before casting IMP. All operations main-thread confined, completions main queue, bounded timeout. Each handle owns only its changes; reversible settings leases, safe stale release. Scene host is real, not screenshots. Define fallback/API limitations explicitly; do not claim touch/focus/assertions proven without runtime. Need actual best-evidence adapter implementations, not a bridge whose entire implementation is unavailable stubs. Research public headers read-only allowed; no execution of sample or device. No broad App mutation. No filter/entry/package edits.

## UI owned by presentation agent

Only `Sources/Presentation/` and `Tests/Presentation/` (except parent may later integrate), `Docs/UI.md`.

Public/internal Swift UIKit iOS15 types:
- `DXRoundedPane: UIView`, `func install(_ hostedView:UIView)`, `func detach()`, `var radius:CGFloat`, `var onInteraction:(() -> Void)?` (observer must not cancel app touches); rounded mask and hit-testing outside corners false. No snapshots.
- `DXStageViewController: UIViewController` with `topPane,bottomPane:DXRoundedPane`; `func setFrames(top:CGRect,bottom:CGRect,topRadius:CGFloat,bottomRadius:CGFloat,animated:Bool,duration:TimeInterval,curve:UIView.AnimationCurve)`; `func setInputFocused(_ slot:DXSlot?, frame:CGRect?, animated:Bool,duration:TimeInterval,curve:UIView.AnimationCurve)`; `func showPicker(applications:[DXApplicationRecord], excluding:String?, selection:@escaping(String)->Void)`; `func dismissPicker()`; closures `onClose,onCollapse,onChooseApplication,onSwitchInput:(()->Void)?`, `onFocus:((DXSlot)->Void)?`. Buttons accessible; input mode single visible pane; picker table/search; messages `func showMessage(_ text:String)`.
- `DXOverlayWindow: UIWindow`, touch pass-through outside actual panes/UI; no keyWindow requirement for remote hosts. Set via rootVC and windowScene in parent. Own mode `var permitsBackgroundHitTesting:Bool` false default.
- `DXEdgeTriggerWindow: UIWindow` with `onTrigger:(()->Void)?`, `var triggerSide: String` (`right` default); only small corner strip hit region, requires upward deliberate pan, route cancellation restores native; parent sets visibility/context. No whole-screen pan swallowing.

Use DXSlot from Core and DXApplicationRecord from bridge. Avoid app launch/platform hooks. Parent coordinator owns animations/async state and keyboard notifications. No private unverified symbols in UI.

## Parent owns

Sources/Coordinator/, Entry/, Input/, Preferences/ (app-side helper if needed); Makefile/control/plists/bridging header; documentation/tests/scripts/archive. Default opt-in setting off, development gating by capability not maximum OS; not inert mandatory runtime verification flag. Settings entry via PreferenceLoader optional bundle can be parent-built, preferences using CFPreferences domain com.tsangbaby.dynamicstagex. Parent integrates API changes after reading agent artifacts.
