#!/usr/bin/env python3
"""Source-only regression checks. NOT a Swift compile, XCTest, or device test."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "Sources" / "Presentation"
REQUIRED_FILES = {
    "DXPresentationGeometry.swift", "DXRoundedPane.swift", "DXStageChrome.swift",
    "DXApplicationPickerViewController.swift", "DXStageViewController.swift",
    "DXOverlayWindow.swift", "DXEdgeTriggerWindow.swift",
}
errors = []
files = {p.name: p.read_text() for p in SOURCES.glob("*.swift")}
for name in sorted(REQUIRED_FILES - files.keys()):
    errors.append("missing file: " + name)
source = "\n".join(files.values())
checks = {
    "DXRoundedPane": r"final class DXRoundedPane\s*:\s*UIView",
    "host install": r"func install\(_ hostedView:\s*UIView\)",
    "host detach": r"func detach\(\)",
    "focus intent": r"var onFocus:\s*\(\(DXSlot\)\s*->\s*Void\)\?",
    "frames API": r"func setFrames\(top: CGRect, bottom: CGRect, topRadius: CGFloat, bottomRadius: CGFloat, animated: Bool, duration: TimeInterval, curve: UIView.AnimationCurve\)",
    "input API": r"func setInputFocused\(_ slot: DXSlot\?, frame: CGRect\?, animated: Bool, duration: TimeInterval, curve: UIView.AnimationCurve\)",
    "picker API": r"func showPicker\(applications: \[DXApplicationRecord\], excluding: String\?, selection: @escaping \(String\) -> Void\)",
    "picker dismiss": r"func dismissPicker\(\)",
    "message API": r"func showMessage\(_ text: String\)",
    "overlay": r"final class DXOverlayWindow\s*:\s*UIWindow",
    "trigger": r"final class DXEdgeTriggerWindow\s*:\s*UIWindow",
}
normalized = re.sub(r"\s+", " ", source)
for name, pattern in checks.items():
    if not re.search(pattern, normalized):
        errors.append("missing contract shape: " + name)
for name in ("onClose", "onCollapse", "onChooseApplication", "onSwitchInput"):
    if not re.search(r"var " + name + r":\s*\(\(\)\s*->\s*Void\)\?", normalized):
        errors.append("missing callback: " + name)
for pattern in (
    r"import\s+SwiftUI", r"\benum\s+DXSlot\b", r"\bclass\s+DXApplicationRecord\b",
    r"\bNSSelectorFromString\b", r"\bunsafeBitCast\b", r"\bdlsym\b",
    r"\bsnapshotView\s*\(", r"\bdrawHierarchy\s*\(", r"\bUIGraphicsImageRenderer\b",
    r"operatingSystemVersion|systemVersion|isOperatingSystemAtLeast",
):
    if re.search(pattern, source):
        errors.append("forbidden dependency/implementation/version gate: " + pattern)
if errors:
    print("FAIL: source contract checks only")
    print("\n".join(errors))
    sys.exit(1)
print("PASS: source contract scans (%d Swift files); not functional proof." % len(files))
print("NOT RUN: Swift/iOS compilation, UIKit XCTest, animation compositor, native hosts/touch/focus.")
