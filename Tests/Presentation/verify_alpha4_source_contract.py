#!/usr/bin/env python3
"""Source-only alpha4 checks. Not a Swift compiler, UIKit run, or hosting proof."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
stage = (ROOT / 'Sources/Presentation/DXStageViewController.swift').read_text()
chrome = (ROOT / 'Sources/Presentation/DXStageChrome.swift').read_text()
checks = 0
errors = []

def check(condition, message):
    global checks
    checks += 1
    if not condition:
        errors.append(message)

check('func setPreparing(_ preparing: Bool, message: String)' in stage, 'missing preparation API')
check('func setPreparationMessage(_ message: String)' in stage, 'missing progress update API')
check('UIActivityIndicatorView(style: .medium)' in chrome, 'missing real activity indicator')
check('DXStagePreparationView' in stage and 'DX.preparation.cancel' in chrome, 'missing standalone progress/cancel')
check('preparationView.cancelButton.addTarget(self, action: #selector(closeTapped)' in stage,
      'preparation cancel is not wired to actual close action')
check('available = !isPreparing && splitLayout != nil' in stage, 'pane readiness gate missing')
check('updateInteractionAvailability()' in stage, 'layout no longer re-applies readiness gate')
check('guard !isPreparing else { return }' in stage, 'picker lacks pending preparation gate')
for action in ['requestFocus', 'collapseTapped', 'chooseTapped', 'switchInputTapped']:
    match = re.search(r'(?:private func|@objc private func) ' + action + r'\([^)]*\) \{([^}]+)', stage)
    check(bool(match and '!isPreparing' in match.group(1)), action + ' allows unready intent')
close = re.search(r'@objc private func closeTapped\(\) \{([\s\S]*?)\n    \}', stage)
check(bool(close and 'isPreparing' not in close.group(1) and 'onClose?()' in close.group(1)),
      'close waits for preparation/native bridge')
for text, name in [(stage, 'stage'), (chrome, 'chrome')]:
    check(not re.search(r'(?:window|view|topPane|bottomPane)\.isUserInteractionEnabled\s*=\s*false', text),
          name + ' globally disables window or pane interaction')
    for forbidden in [r'\bNSSelectorFromString\b', r'\bunsafeBitCast\b', r'\bUIWindow\s*\(',
                      r'\bsnapshotView\s*\(', r'\bmakeKeyAndVisible\b', r'\bUIProgressView\b',
                      r'operatingSystemVersion|systemVersion|isOperatingSystemAtLeast']:
        check(not re.search(forbidden, text), name + ': forbidden implementation ' + forbidden)
check('end - start >= 44' in chrome and 'safe.contains(frame)' in chrome,
      'toolbar no longer bounds to real reserved region')
check('focused.minY - safe.minY >= 52' in chrome and 'frame.minY + 8' not in stage,
      'input toolbar still falls back inside app content')
check('frame.intersects(top)' in chrome and 'frame.intersects(bottom)' in chrome,
      'toolbar has no final pane overlap guard')
check('return nil\n    }\n}' in chrome, 'root lost its outside-pane/chrome pass-through')

if errors:
    print('FAIL: alpha4 source checks only; ' + '; '.join(errors))
    sys.exit(1)
print(f'PASS: {checks} alpha4 source-only checks; not functional proof.')
print('NOT RUN: Swift/iOS compilation, UIKit XCTest/smoke, private Scene/event readiness, physical device.')
