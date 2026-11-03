# Alpha3 — visible trigger marker does not respond

## Observation vs root cause

User confirmed alpha2 Settings works, and the selected corner marker is visible, but swiping it did not open split view. That confirms visibility, not touch delivery, pan acceptance, Coordinator eligibility or real Scene authority. Small hit area/strict thresholds are source findings, not by themselves a proven device root cause. No phone was attached or instrumented.

Alpha2's delegate required a custom initial displacement AND velocity while UIPan was deciding to leave `.possible`; a tiny/zero first sample could fail the entire sequence. Its elapsed minimum was measured after recognition, not physical touch-down, excluding a fast valid release. Independent source review also found same-side reassignment cancelling the recognizer and trigger entry swallowing all gate failures. Those failure mechanisms have separate tests and remain distinguished from SpringBoard event routing.

## Scoped repair

- Reserve a 64×88pt corner strip above Home (was32×56pt), while retaining a small visible marker. Only the configured left OR right side is active; do not add a screen-wide touch surface.
- UIPan owns initial movement slop. Admit finite undecided starting samples; evaluate deliberate upward intent at release: ≥48pt up, bounded sideways drift, ≤2.8s after recognition. No minimum recognized-duration or minimum upward speed. Invalid/nonfinite input is rejected.
- Assigning the same normalized side is idempotent and does not toggle recognizer.isEnabled. Actually switching side, hiding, disabling or losing context still cancels.
- The marker turns blue only when a real `.began` action arrives. Release rejection produces a bounded hint; recognition success still uses the normal onTrigger callback.
- Coordinator uses a production Foundation eligibility policy; missing frontmost, Home, missing/ambiguous display Scene, busy/dismiss/state conflict and wrong orientation are reported instead of silently returning. Unknown lock state remains fail-closed, never unlock or display over a locked screen.
- No key-window grab, HID event fabrication, private Scene/keyboard ABI loosening, App-wide dimensions or maximum-OS gate were added. The system bridge is byte-identical to alpha2.
- Keep the already-working alpha2 Preferences architecture, stored keys and write notifications. Only visible package/bundle version markers advance toalpha3.

## Real-input regression contract

`Tests/TriggerHarness` builds a minimal foreground UIKit test app containing byte-identical copies of the production edge window and geometry. An ordinary window stays key; the trigger window remains non-key. Public XCUICoordinate press/drag operations send actual simulator touch sequences. No recognizer state injection, direct onTrigger invocation or accessibilityActivate substitute is accepted as a swipe test.

The suite checks left/right ordinary and slow upward strokes, shorter/deliberately diagonal rejection, tap/horizontal/downward rejection, repeated same-side assignments during a drag, disabled-context behavior and outside-region background button/pan routing. Simulator UIKit behavior does not prove SpringBoard/WindowServer delivery on a jailbroken phone. Failed or incomplete tests with empty/ignored test results are not reported as passes.

Foundation tests cover the production Coordinator eligibility decision, including every denial reason, malformed app IDs and external state. Existing Settings UIKit regression, core tests, production C ABI/lease tests, real dual-architecture iOS build and independent package gate remain required.

## Artifact and device boundary

Build only from `fix/trigger-alpha3`; keep main, originalalpha1 and testedSettingsalpha2 unchanged. No merge/Release/device connection/attach/install/respring. Initial source manifest is historical; use current Git commit and exact artifact digest for this candidate.

Use the configured marker in a portrait App, not the Home indicator. Blue during the movement means the gesture began; an exact error after release means the trigger was recognized but a later gate/capability failed. A marker that never changes needs a separate real event-routing diagnosis, not repeated advice to swipe harder. An accepted gesture and even an opened picker do not prove full remote touch/keyboard compatibility.

CI results, artifact SHA256 and native package validation are reported only after actual completion.
