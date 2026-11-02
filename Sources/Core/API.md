# DynamicStageXCore public API

Foundation-only production Swift; Swift 5 language mode, iOS 15.0 minimum, no upper OS gate. `Package.swift` builds only `Sources/Core` and XCTest tests in `Tests/Core`. All declarations listed below are `public`. Geometry uses Double points in a **single caller-converted coordinate space**, never pixels. No UIKit, private API, hosting, focus transfer, timers, or scene ownership are implied by this module.

## Geometry and layout

- `DXSlot: String, CaseIterable, Hashable`: `.top`, `.bottom`.
- `DXInsets: Equatable`: immutable `top,left,bottom,right: Double`; `init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0)`; `static let zero`; `var isValid: Bool` (finite, nonnegative).
- `DXRect: Equatable`: immutable `x,y,width,height: Double`; `init(x:y:width:height:)`; `static let zero`; `minX,minY,maxX,maxY: Double`; `isFinite,isValid,hasArea: Bool`; `contains(x:y:) -> Bool`; `contains(_ other: DXRect) -> Bool`; `intersection(_ other: DXRect) -> DXRect?`; `inset(by: DXInsets) -> DXRect?`.
  - `isValid` permits zero dimensions but rejects negative dimensions and overflowed endpoints. `hasArea` also requires representably positive extents. Intersection/inset require positive area. Touching edges have no intersection. Contains includes edges but rejects invalid/empty rectangles and nonfinite points.
- `DXRoundedHitTest.contains(x: Double, y: Double, in bounds: DXRect, radius: Double) -> Bool`: circular four-corner clipping; finite nonnegative radius, clamped to half the smaller dimension. This is **not** a mathematical model of UIKit's continuous corner curve; UI must use the same path if it uses this helper for exact hit testing.
- `DXLayout: Equatable`: immutable `top,bottom: DXRect`, `topRadius,bottomRadius: Double`; `init(top:bottom:topRadius:bottomRadius:)`.
- `DXLayoutPolicy.split(bounds: DXRect, safeArea: DXInsets, ratio: Double, gap: Double, margin: Double, radius: Double) -> DXLayout?` (static).
  - Safe-area inset first, then equal outer margin. Ratio is top share of height **after** the gap; must be strictly between 0 and 1. Gap/margin/radius must be finite and nonnegative. Invalid/unrepresentable/empty layouts fail, never silently repair negative geometry. Both pane radii clamp independently. No transforms/content compression.

## Keyboard policy

- `DXKeyboardOcclusion: Equatable`: `.none`, `.docked(DXRect)`, `.floating(DXRect)`; `var frame: DXRect?`.
- `DXKeyboardPolicy.occlusion(bounds: DXRect, safeArea: DXInsets, keyboard: DXRect, edgeTolerance: Double = 1) -> DXKeyboardOcclusion?` (static).
  - Nil = invalid geometry. `.none` = no software obstruction of usable content, including hardware/zero-height or offscreen frames. Frames are clipped to bounds and usable safe-area content. Docked means spans usable width and reaches the **display bounds bottom**, within tolerance; a narrow bottom-touching float is not docked.
- `DXKeyboardPolicy.isDocked(keyboard: DXRect, bounds: DXRect) -> Bool` (static): convenience classification with zero safe-area and default tolerance.
- `DXKeyboardPolicy.focusedFrame(bounds: DXRect, safeArea: DXInsets, keyboard: DXRect, minimumHeight: Double) -> DXRect?` (static).
  - Returns safe-area frame above an actual docked keyboard only; minimumHeight must be finite and positive. Nil also means **no promotion** for floating/hardware/no-obstruction. Call `occlusion` first to distinguish these from invalid/too-small cases; do not treat every nil as a request to leave native input.
- `DXKeyboardPolicy.unobscuredRegions(in frame: DXRect, avoiding keyboard: DXRect) -> [DXRect]` (static): up to four nonoverlapping positive rectangles subtracting the actual footprint; no intersection returns `[frame]`, invalid input returns `[]`. Floating-keyboard policy can offer these local regions to app-side scrolling without globally shortening the display or promoting a pane. Parent retains split layout for `.floating`/`.none`.

## Session and generation state machine (preferred Bool interface)

`DXSessionToken: Hashable`: immutable `sessionID: UUID`, `generation: UInt64`; `init(sessionID: UUID = UUID(), generation: UInt64 = 0)`.

`DXPhase: String, CaseIterable, Hashable`: `.idle, .selecting, .preparing, .split, .inputFocused, .collapsed, .dismissing`.

`DXStateMachine` is a value type; parent serializes all access (normally main queue). Public read-only `phase: DXPhase`, `token: DXSessionToken?`, `generation: UInt64`, `focusedSlot: DXSlot?`; `init()` starts idle, nil token, generation 0.

Exact methods:

```swift
func isCurrent(_ token: DXSessionToken) -> Bool
mutating func beginSelection() -> DXSessionToken?
mutating func prepare(token: DXSessionToken) -> Bool
mutating func splitReady(token: DXSessionToken) -> Bool
mutating func focus(token: DXSessionToken, slot: DXSlot) -> Bool
mutating func clearFocus(token: DXSessionToken) -> Bool
mutating func collapse(token: DXSessionToken) -> Bool
mutating func resume(token: DXSessionToken) -> Bool
mutating func beginDismiss(token: DXSessionToken) -> Bool
mutating func finishDismiss(token: DXSessionToken) -> Bool
mutating func renew(token: DXSessionToken) -> DXSessionToken?
```

**Important: tokens are operation snapshots, not stable session-only UUIDs. Every actual transition advances generation and replaces `state.token`. After a successful Bool transition, capture the NEW `state.token` for any callbacks. Never keep passing the old local token across transitions.** A stale token, invalid transition, or UInt64 exhaustion returns false/nil with no state mutation. No wraparound; the last two generations are reserved for dismissal so exhaustion cannot trap an active session. Session UUID stays the same until the next beginSelection from idle.

- `beginSelection`: idle → selecting, new UUID.
- `prepare`: selecting/preparing/split/inputFocused/collapsed → preparing; supports retry/replacement; clears focus. Even preparing → preparing advances generation.
- `splitReady`: preparing → split.
- `focus`: split/inputFocused → inputFocused; records slot. Even same-slot focus advances generation to supersede old keyboard/layout work.
- `clearFocus`: inputFocused → split; current split is accepted without generation change.
- `collapse`: split/inputFocused → collapsed; clears focus. Current collapsed accepted unchanged.
- `resume`: collapsed/inputFocused → split; clears focus. Current split accepted unchanged.
- `beginDismiss`: any active state → dismissing; clears focus. Current dismissing accepted unchanged.
- `finishDismiss`: dismissing → idle, nil token; generation advances. Exact repeated completion with the just-finished dismissal token is accepted unchanged **only while still idle**. An old finish cannot dismiss a new session.
- `renew`: advances generation without changing phase/focus; allowed in every active phase except dismissing. Use before a replacement same-phase async operation/frame animation. `isCurrent` compares UUID **and generation**, and is false in idle.

Integration pattern (callbacks dispatched back to parent's serial executor):

```swift
guard let selection = state.beginSelection(),
      state.prepare(token: selection),
      let preparation = state.token else { return }
// Capture preparation for the whole bounded acquisition batch.
// On each completion: guard state.isCurrent(preparation), else release only
// the newly returned owned resource. Aggregate both hosts before splitReady.
// if state.splitReady(token: preparation) { capture state.token again }
```

State flags are policy, not evidence that a scene has actually focused/mounted. Confirm the bridge result before committing split/focus. Close invalidates old work immediately; stale resources must still be released, never merely ignored.

## Bounded ownership helpers

- `DXCancellation` (final class): `init(_ action: @escaping () -> Void)`; thread-safe `isCancelled: Bool`; `cancel() -> Bool`. Exactly one caller takes the action, outside the lock; true means this call ran it. Deinit cancels. Reentrant cancellation is safe. Cleanup must return promptly; it runs synchronously on the cancelling thread (including deinit), so parent must explicitly close UI-related ownership on its main executor. No blocking deadline/scheduler is provided.
- `DXResourceBag` (final class): `static let maximumCapacity = 256`; read-only `capacity: Int`, thread-safe `count: Int`, `isClosed: Bool`; `init(capacity: Int = 64)` clamps into 0...256; `insert(_ resource: DXCancellation) -> Bool`; `removeAndCancel(_ resource: DXCancellation) -> Bool`; `close() -> Bool`.
  - Holds strong cleanup leases; duplicate identity inserts are accepted once. Cancelled resources are not accepted. Full/closed insertion immediately cancels rejected ownership, outside the lock. Remove cancels only if owned. Close is terminal/idempotent, clears storage before LIFO cleanup; true only for first close. Deinit closes. Cleanup may safely reenter the bag. Explicitly close one bag per operation/session on cancellation, timeout, collapse retention expiry, or dismissal; parent supplies bounded timers and performs `isCurrent` checks. Avoid action→owner→bag retain cycles (use weak captures); helpers cannot cancel a cycle that prevents deinit.

## Verification status

`Tests/Core/*.swift` are XCTest tests directly importing this production target, not a parallel geometry/state implementation. Run `swift test` with a supported installed Swift toolchain; no Swift compiler is available in the current iSH environment. `python3 Tests/Core/verify_source_contract.py` is only a local source-contract check, never a Swift compilation, native XCTest result, iOS build, private-API proof, or device/hosting validation.
