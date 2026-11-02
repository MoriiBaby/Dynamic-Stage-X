#!/usr/bin/env python3
"""Repository contracts only. No native compilation, UIKit execution or device access."""
from pathlib import Path
import json
import plistlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SourceContracts(unittest.TestCase):
    def text(self, path):
        return (ROOT / path).read_text()

    def test_identity(self):
        fields = {}
        for line in self.text('control').splitlines():
            if ':' in line:
                key, value = line.split(':', 1)
                self.assertNotIn(key, fields)
                fields[key] = value.strip()
        self.assertEqual(fields['Package'], 'com.tsangbaby.dynamicstagex')
        self.assertEqual(fields['Name'], 'Dynamic Stage X')
        self.assertIn('firmware (>= 15.0)', fields['Depends'])
        self.assertNotIn('<<', fields['Depends'])
        self.assertNotIn('rootless-compat', fields.get('Pre-Depends', ''))
        self.assertNotIn('Installed-Size', fields)

    def test_plists_and_injection(self):
        for path in ROOT.glob('**/*.plist'):
            if 'evidence' in path.parts:
                continue
            with path.open('rb') as stream:
                plistlib.load(stream)
        with (ROOT / 'DynamicStageX.plist').open('rb') as stream:
            self.assertEqual(plistlib.load(stream)['Filter']['Bundles'], ['com.apple.springboard'])
        with (ROOT / 'Preferences/Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        self.assertEqual(info['MinimumOSVersion'], '15.0')
        self.assertEqual(info['NSPrincipalClass'], 'DXPreferencesController')
        with (ROOT / 'layout/Library/PreferenceLoader/Preferences/DynamicStageX.plist').open('rb') as stream:
            entry = plistlib.load(stream)['entry']
        self.assertEqual(entry['bundle'], 'DynamicStageXPrefs')
        self.assertTrue(entry['isController'])

    def test_build_source_closure(self):
        make = self.text('Makefile')
        self.assertIn('TARGET = iphone:clang:latest:15.0', make)
        self.assertIn('ARCHS = arm64 arm64e', make)
        self.assertIn('DynamicStageX_OBJCFLAGS = -fobjc-arc', make)
        self.assertNotIn('DynamicStageX_CFLAGS = -fobjc-arc', make)
        self.assertIn('DynamicStageXPrefs_RESOURCE_FILES = Preferences/Info.plist', make)
        self.assertIn('DynamicStageXPrefs_SWIFT_BRIDGING_HEADER = Preferences/DynamicStageXPrefs-Bridging-Header.h', make)
        for path in ROOT.glob('Sources/**/*'):
            if path.suffix in ('.m', '.c', '.swift'):
                self.assertEqual(len(path.relative_to(ROOT).parts), 3, str(path))
        self.assertIn('Sources/System/DXSystemBridge.h', self.text('DynamicStageX-Bridging-Header.h'))

    def test_entry_symbols_match(self):
        entry = self.text('Sources/Entry/DXEntry.m')
        coordinator = self.text('Sources/Coordinator/DXCoordinator.swift')
        for symbol in ['DXSwiftStart', 'DXSwiftPreferencesChanged', 'DXSwiftContextChanged']:
            self.assertIn('extern void ' + symbol + '(void)', entry)
            self.assertIn('@_cdecl("' + symbol + '")', coordinator)
        self.assertIn('com.apple.springboard', entry)

    def test_no_runtime_reference_copy_or_upper_gate(self):
        paths = list(ROOT.glob('Sources/*/*')) + list(ROOT.glob('Preferences/*.swift'))
        for path in paths:
            if path.suffix not in ('.swift', '.m', '.h', '.c'):
                continue
            text = path.read_text()
            self.assertNotRegex(text, r'me\.tomt000|pkgmirror|AutoPatches|rootless-compat')
            self.assertNotRegex(text, r'snapshotViewAfterScreenUpdates|UIGraphicsImageRenderer|AVPlayer')
            self.assertNotRegex(text, r'(?:majorVersion|operatingSystemVersion)\s*[><=]')
            self.assertNotRegex(text, r'\b(?:TODO|FIXME|fatalError)\b')
        self.assertFalse((ROOT / '.github/workflows').exists())

    def test_state_and_cleanup_integration(self):
        source = self.text('Sources/Coordinator/DXCoordinator.swift')
        self.assertIn('token = machine.token', source)
        self.assertIn('sceneCommands.cancelPending()', source)
        self.assertIn('defer { staging.removeFromSuperview() }', source)
        self.assertIn('generation == expected', source)
        self.assertIn('geometrySerial == revision', source)
        self.assertIn('keyboardFocusProcessIdentifier()', source)
        self.assertIn('pending', self.text('Sources/Coordinator/DXSceneCommandQueue.swift'))
        self.assertIn('DXKeyboardPolicy.focusedFrame', source)
        self.assertIn('bridge.release(handle)', source)
        self.assertIn('window.isUserInteractionEnabled = false', source)

    def test_privacy_and_defaults(self):
        self.assertIn('var enabled = false', self.text('Sources/Preferences/DXPreferences.swift'))
        sources = '\n'.join(p.read_text() for p in ROOT.glob('Sources/*/*') if p.suffix in ('.swift','.m','.c','.h'))
        self.assertNotRegex(sources, r'\b(?:UIPasteboard|NSURLSession|URLSession|AVCapture|CTTelephonyNetworkInfo)\b')
        self.assertIsNone(re.search(r'\bmakeKeyAndVisible\s*\(', sources), 'remote overlay must not make itself key and visible')

if __name__ == '__main__':
    print('SOURCE CONTRACTS ONLY; not Swift/iOS compilation or runtime verification.', flush=True)
    unittest.main(verbosity=2)
