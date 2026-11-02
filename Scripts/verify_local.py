#!/usr/bin/env python3
"""Run local source contracts and C-only tests. Never builds/installs an iOS product."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--grammar-python', type=Path, help='Python containing optional tree-sitter modules')
args = parser.parse_args()
reports = ROOT / 'Reports'
reports.mkdir(exist_ok=True)
commands = [
    ('source-contracts', [sys.executable, 'Scripts/check_source.py']),
    ('core-source-contracts', [sys.executable, 'Tests/Core/verify_source_contract.py']),
    ('presentation-source-contracts', [sys.executable, 'Tests/Presentation/verify_source_contract.py']),
    ('bridge-C-and-evidence', ['sh', 'Tests/Bridge/run-local.sh']),
]
if args.grammar_python:
    commands.append(('swift-grammar-only', [str(args.grammar_python), 'Scripts/check_swift_grammar.py',
                                           '--output', str(reports / 'swift-grammar.json')]))
results = []
for name, command in commands:
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=240)
    log = reports / (name + '.txt')
    log.write_text('COMMAND: ' + ' '.join(command) + '\nSTDOUT:\n' + done.stdout + '\nSTDERR:\n' + done.stderr)
    results.append({'check': name, 'returncode': done.returncode, 'log': str(log.relative_to(ROOT))})
    print(name + ': ' + ('PASS' if done.returncode == 0 else 'FAIL'))
    if done.returncode:
        print((done.stdout + done.stderr)[-4000:])
summary = {
    'product': 'Dynamic Stage X', 'package': 'com.tsangbaby.dynamicstagex',
    'source_version': '0.1.0-alpha1', 'checks': results,
    'scope': 'C production policy execution, source contracts and optional Swift grammar only',
    'swift_compiler_available': shutil.which('swiftc') is not None,
    'xcrun_available': shutil.which('xcrun') is not None,
    'swift_XCTest_executed': False, 'iOS_build_executed': False,
    'device_actions_executed': False, 'remote_writes_executed': False,
    'all_requested_local_checks_passed': all(x['returncode'] == 0 for x in results)
}
(reports / 'local-verification.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False) + '\n')
sys.exit(0 if summary['all_requested_local_checks_passed'] else 1)
