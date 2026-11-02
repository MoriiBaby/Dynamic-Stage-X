#!/usr/bin/env python3
"""Source-contract checks only. Does NOT compile or execute production Swift."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ["DXGeometry.swift", "DXLayoutPolicy.swift", "DXKeyboardPolicy.swift",
           "DXStateMachine.swift", "DXLifetime.swift"]
TESTS = ["DXGeometryTests.swift", "DXKeyboardPolicyTests.swift",
         "DXStateMachineTests.swift", "DXLifetimeTests.swift"]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def swift(relative):
    # Lexical check, not a Swift parser: ignore comments and escaped string contents.
    text = read(relative)
    return re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"', "", text)


class SourceContractTests(unittest.TestCase):
    def test_production_uses_only_foundation(self):
        for name in SOURCES:
            text = swift("Sources/Core/" + name)
            self.assertEqual(re.findall(r"^import\s+(\w+)", text, re.M), ["Foundation"])
            self.assertNotRegex(text, r"\b(?:UIKit|CGFloat|CGRect|NSClassFromString|unsafeBitCast|fatalError)\b")
            self.assertNotRegex(text, r"#available|@available|#if\s+os")
            self.assertNotRegex(read("Sources/Core/" + name), r"\b(?:TODO|FIXME)\b")

    def test_manifest_is_core_only(self):
        text = read("Package.swift")
        self.assertIn("swift-tools-version: 5.5", text)
        self.assertIn("platforms: [.iOS(.v15)]", text)
        self.assertIn('path: "Sources/Core"', text)
        self.assertIn('path: "Tests/Core"', text)
        self.assertIn('exclude: ["API.md"]', text)
        self.assertIn('exclude: ["verify_source_contract.py"]', text)
        self.assertNotIn(".package(", text)

    def test_public_types_exist(self):
        text = "\n".join(swift("Sources/Core/" + name) for name in SOURCES)
        for name in ["DXRect", "DXInsets", "DXSlot", "DXLayout", "DXLayoutPolicy",
                     "DXRoundedHitTest", "DXKeyboardPolicy", "DXKeyboardOcclusion",
                     "DXSessionToken", "DXPhase", "DXStateMachine", "DXCancellation", "DXResourceBag"]:
            self.assertRegex(text, r"public (?:final )?(?:struct|enum|class) " + name + r"\b")

    def test_preferred_state_and_keyboard_contract(self):
        text = swift("Sources/Core/DXStateMachine.swift")
        self.assertRegex(text, r"public mutating func beginSelection\(\) -> DXSessionToken\?")
        self.assertRegex(text, r"public func isCurrent\(_ token: DXSessionToken\) -> Bool")
        for name in ["prepare", "splitReady", "clearFocus", "collapse", "resume", "beginDismiss", "finishDismiss"]:
            self.assertIn("public mutating func " + name + "(token: DXSessionToken) -> Bool", text)
        self.assertIn("public mutating func focus(token: DXSessionToken, slot: DXSlot) -> Bool", text)
        self.assertIn("UInt64.max - 2", text)
        keyboard = swift("Sources/Core/DXKeyboardPolicy.swift")
        self.assertIn("public static func isDocked(keyboard: DXRect, bounds: DXRect) -> Bool", keyboard)
        self.assertIn("return DXKeyboardOcclusion.none", keyboard)

    def test_xctests_import_real_target(self):
        total = 0
        for name in TESTS:
            text = swift("Tests/Core/" + name)
            self.assertIn("import XCTest", text)
            self.assertIn("import DynamicStageXCore", text)
            self.assertNotRegex(text, r"(?:struct|class|enum) DX(?:Rect|StateMachine|LayoutPolicy)\b")
            total += len(re.findall(r"func test\w+\(", text))
        self.assertGreaterEqual(total, 28)

    def test_delimiters_balance_lexically(self):
        files = ["Package.swift"] + ["Sources/Core/" + n for n in SOURCES] + ["Tests/Core/" + n for n in TESTS]
        for name in files:
            stack = []
            for char in swift(name):
                if char in "([{":
                    stack.append(char)
                elif char in ")]}":
                    self.assertTrue(stack, name)
                    self.assertEqual(stack.pop(), {")": "(", "]": "[", "}": "{"}[char], name)
            self.assertFalse(stack, name)


if __name__ == "__main__":
    print("SOURCE CONTRACT ONLY; Swift compilation and XCTest execution are NOT performed.", flush=True)
    unittest.main(verbosity=2)
