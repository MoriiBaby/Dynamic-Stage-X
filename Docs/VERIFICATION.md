# Verification — source delivery

## What was actually run

Local verification commands are collected by `Scripts/verify_local.py`; exact return codes and per-command logs are in `Reports/local-verification.json` and adjacent `.txt` files.

- Repository identity/metadata/deployment/source contract checks: **7 tests passed**.
- Foundation-core source contracts: **6 tests passed**; this is not Swift execution.
- Presentation interface/source checks: **7 Swift files checked**, passed; this is not UIKit execution.
- Real host C compilation (`cc -std=c11 -Wall -Wextra -Werror -pedantic -O2`) and execution of the **production ABI encoding and lease-restore policy**: **21,053 checks passed**.
- Local public-header evidence cache: **93 SHA256 checks /14 declaration mappings passed**. These pin source declarations, not device ABI or behavioral proof. Raw third-party header caches are not part of the delivered source ZIP; fetch scripts/URLs/hashes remain available. Without that optional cache, the test must report that evidence verification did not run rather than claiming success.
- Swift grammar parsed by tree-sitter **0.25.2** + tree-sitter-swift **0.7.4**. All enumerated Swift files passed with no grammar-error/missing nodes. Current file count is in `Reports/swift-grammar.json`; this is not Swift compiler typechecking, imported ObjC-name validation, linking, UIKit layout or runtime testing.

## Tests written but not executed

- Production Foundation Swift XCTest cases under `Tests/Core/` (29 test methods).
- UIKit presentation XCTest source under `Tests/Presentation/`; requires an iOS test host and production UI/Core sources plus bridge header.
- Full Swift/ObjC/UIKit build, actual arm64/arm64e linkage/signatures and DEB package checks.
- Device Scene hosting, real user touches, keyboard delivery/focus, geometry acknowledgement, interrupted restoration, visual round-corner/compositor and performance matrices.

The current environment has no `swift`, `swiftc` or `xcrun`. No source scan or syntax parser output is substituted for these missing results.

## Failures encountered and addressed

- A first source assertion rejected the *word* `makeKeyAndVisible` in a comment that said not to use it. The check now looks for an actual call. The overlay was separately changed to be permanently non-key, with no keyboard search in the app picker, to preserve remote input ownership.
- A temporary Python venv on the shared filesystem failed because symlink creation was not permitted. A `/tmp` venv was used instead. The initial tree-sitter0.26 source build timed out; no parser was installed by that failed attempt. The pinned0.25.2 installation succeeded and produced the actual grammar results.
- Integration review corrected operation-generation handoff, initial window visibility before native event binding, attached staging for a new real host, temporary3-lease replacement capacity, busy-operation cleanup ownership, serialized geometry/focus, native cold-start reconstruction order and late cleanup barriers.
- Theos recipe review corrected ARC to ObjC-only flags, explicit preference bridging header and the supported resource-file variable for `Info.plist`. This did not run Theos or prove compilation.

## Scope preserved

Only local source/evidence/tests/archive work. No Git repository/commit/push, CI run, remote publishing, device connection/attach, installation or respring. Input attachments were not modified or copied into the source archive.
