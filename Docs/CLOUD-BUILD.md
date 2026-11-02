# Cloud native RootHide build — alpha1

User authorized macOS cloud build and delivery of a RootHide test package on2026-11-02. Work is isolated on `build/roothide-alpha1`; main keeps the original75-file source snapshot. This authorization does not include merging, creating a Release, installing, attaching to or restarting a device.

## Build contract

- GitHub-hosted macos-15; explicitly select Xcode16.4 and record actual Xcode/Swift/Clang/macOS versions.
- Official `roothide/theos` pinned to `cfba89a53a05b4a1b822121158acc3669c20602f`, recursive submodules at its recorded gitlinks.
- `theos/sdks` pinned to `0222fd5413cf4b9af096f37b4621afa2688572f7`; select directory iPhoneOS16.5.sdk, whose actual SDKSettings declares iOS16.4. Build target is explicitly `iphone:clang:16.5:15.0`, not the newest SDK found by Theos.
- Genuine arm64 and arm64e; firmware minimum15.0; no maximum OS gate. NativeRootHide scheme, not a convertedrootless package.
- Homebrew packaging utilities versions are recorded at build time. This is traceable, not a fully bit-reproducible environment.
- Run source/C contracts and the production FoundationSwift XCTest target before compiling/signing/packaging both iOS modules.
- Source grammar/native test status from the initial snapshot is historical. Actual build logs and artifact evidence from this workflow supersede the corresponding “not run” items only after success.

The generated `SOURCE-MANIFEST.json` is intentionally the original immutable source delivery record, not a claim that subsequent CI/fix files still match that old source. The git commit and cloud artifact manifest identify the new test candidate.

## Success/failure signals

The workflow must have terminal conclusion success, package identity/inventory checks must pass, and the downloaded artifact must independently matchGitHub's SHA256 digest. Local inspection verifies actual DEB structure, bothMach-O architectures/minOS/dependencies/signatures; no success is inferred merely from HTTP200 or an uploaded diagnostics ZIP. Compiler errors are fixed minimally on this branch and re-run. Real host/touch/keyboard and lifetime acceptance remains a separate user device test.

No GitHub write token is embedded in workflow/scripts. Checkout does not persist authentication; workflow permissions are contents:read. Artifacts include only DEB/build logs/metadata, no original sample/video, raw header cache or credentials.
