# Known limitations and unverified behavior

This file distinguishes written source from a tested iOS product. No code path is advertised as device-verified in this source delivery.

## Mandatory next verification layer

- Swift/Objective-C/UIKit compilation has not run. Imported method naming, framework availability and actual toolchain diagnostics remain to be checked.
- Private runtime declarations are source candidates with exact ABI gates. Calling conventions can be checked; semantic compatibility, system policy and real event delivery still require devices across the supported target range.
- iOS15.0+ is the development target, no maximum-version gate. No system version is currently marked as live split-view verified. Failure to resolve a primitive is reported; unsupported ABI is not invoked.

## Current functionality boundaries

1. Portrait/default1:1/two different apps. Landscape, arbitrary divider drag, same-App multi-Scene and free multiple windows are not this first source scope.
2. Live hosting requires native presenter, main-display host/event-binding, active Scene and foreground-process acknowledgement. The adapter refuses raw pixel-only fallback. Some systems/apps may reject these requirements; this is not bypassed by fake views.
3. Cold applications use release-all → normal native activation → confirm unique active Scene → reacquire original top and selected bottom. A brief native launch transition may be visible. Pure background cold launch without this transition is not implemented by guessing a private request ABI.
4. App picker is a sorted list with a local alphabetical index, not a keyboard search field. Making the plugin overlay key during a search could steal remote input ownership. That feature needs a dedicated focus handshake before enabling it.
5. Keyboard frame updates currently come from system UIKit notifications received in SpringBoard, accepted only when authoritative focus PID belongs uniquely to a live plugin session. Delivery completeness for third-party keyboards and each iOS version is **unverified**. No global App injection or unauthenticated IPC is used to hide this gap. Floating/hardware keyboards retain split layout; responder auto-scroll behavior needs app testing.
6. A keyboard focus identity does not identify an input text field or force an App's responder. Switching window focus requests native focus; the user may still need to tap the destination input field.
7. A native host can bypass ordinary view masking or implement remote hit-testing differently. The custom continuous mask and matching hit path are written, but actual hosted content clipping/corner touch exclusion requires native validation.
8. Edge trigger occupies only a small corner strip and is cancelled on context loss. Once UIKit delivers touches to that strip it cannot replay a failed stream to an underlying App or system gesture; it is not a universal system gesture arbiter.
9. Collapsed state has a120-second retention limit; memory warning/context loss ends the session. It is not unlimited background residence. No camera/DRM/audio policy hacks or all-App iPad spoofing are included.
10. Defaults are conservative: opt-in off, 28pt radius starting value,6pt gap,4pt outer margin. They are original tuning choices, not recovered constants from the reference product.

## Cleanup and failures

Settings restoration only writes fields still owned by the plugin. An external system owner winning a race is not overwritten. Restoration errors are reported, and automatic native fallback is not attempted after an unconfirmed cleanup. User/system context interruption never blindly relaunches a previous App on top of Home or another foreground App.

The code has no automatic uploaded telemetry, networking, input-text capture, clipboard read, screenshots, private credentials, automatic installation or respring. Any future application-side helper must be scoped to a verified active Scene and authenticated sender; it is not present as an inert module claiming to fix all apps.
