# Build and verification boundaries

## Current source delivery

Source candidate only. No Theos build, linker run, DEB packaging, CI, upload, install or respring was executed. The local iSH environment has Clang/Python but no `swiftc`, `xcrun` or Apple UIKit SDK. Tree-sitter parses grammar, not Swift types or imported Objective-C names.

## Required native environment

- Trusted macOS/Xcode toolchain capable of targeting **iOS15.0** and generating genuine arm64 + arm64e.
- A pinned Theos checkout matching the intended package scheme; RootHide must use native RootHide Theos support.
- Appropriate iOS SDK and Preferences compile declarations. No SDK or third-party runtime is redistributed in this source.
- PreferenceLoader at runtime. The private bridge uses runtime lookup, not strong linking of private Objective-C classes. A future build must still inspect strong/weak symbols and dyld dependencies.

The source Makefile uses `iphone:clang:latest:15.0`; **SDK/compiler are not pinned or verified by this source-only turn**. Select and lock a deployable combination when a build is requested, record actual SDK metadata rather than treating directory names as SDK versions. An explicit15.0 deployment target must be checked in each built slice and bundle.

## Future build commands (not executed)

```sh
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

`make package` is not `make install`. Do not use the latter, or restart SpringBoard, without a separate device instruction. There is no CI workflow in this tree.

Default `control` Architecture is `iphoneos-arm64e`, matching the proposed native RootHide variant. A rootless source build requires rootless-native Theos plus correct `iphoneos-arm64` package metadata; rootful has its own install layout. Never rename a built archive or just edit its Architecture and call it a native conversion. Do not publish a package until scheme-generated layout/dependencies and metadata are checked.

Theos variable choices were checked read-only against upstream `makefiles/instance/rules.mk` and `makefiles/instance/shared/bundle.mk` on2026-11-02: `_SWIFT_BRIDGING_HEADER` imports custom headers and `_RESOURCE_FILES` copies `Preferences/Info.plist` into the bundle. These are source build-recipe checks, not an assertion of native build success.

## Native acceptance after a future build

1. Run production Swift tests with `swift test` (Foundation core only).
2. Compile UIKit presentation tests in an iOS test host with product sources and the bridge header. They do not run in the Foundation-only package.
3. Inspect both Mach-O slices: CPU subtype, minOS15.0, imported runtime/framework symbols, code-page signatures and constructors. The package architecture field is not CPU proof.
4. Check actual DEB control uniqueness, native scheme paths, PreferenceLoader entry/Info principal class, no accidental copy of evidence/SDK/test binaries.
5. Device validation must independently confirm live content, user touch delivery, focus/keyboard, read-back geometry and owned restoration. API metadata matching does not replace this.
