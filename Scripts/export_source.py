#!/usr/bin/env python3
"""Create a verified source-only snapshot. No Git, remote upload or device actions."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
if args.output.exists():
    raise SystemExit('Refusing to overwrite an existing source snapshot')
verification = json.loads((ROOT / 'Reports/local-verification.json').read_text())
if not verification['all_requested_local_checks_passed']:
    raise SystemExit('Local checks did not all pass; snapshot withheld')
excluded_parts = {'.git', '.theos', '.build', '__pycache__', 'packages'}
forbidden_suffixes = {'.deb', '.dylib', '.ipa', '.mp4', '.mov', '.png', '.jpg', '.jpeg', '.pyc', '.o', '.a'}
raw = subprocess.check_output(['rg', '--files', '--hidden', '--no-ignore', str(ROOT)], text=True)
files = []
for line in raw.splitlines():
    path = Path(line)
    relative = path.relative_to(ROOT)
    if any(part in excluded_parts for part in relative.parts):
        continue
    if str(relative).startswith('Tests/Bridge/evidence/') or relative.name == 'SOURCE-MANIFEST.json':
        continue
    if path.is_symlink() or not path.is_file():
        raise SystemExit('Only regular source files may be exported: ' + str(relative))
    if path.suffix.lower() in forbidden_suffixes:
        raise SystemExit('Unexpected binary/media in source tree: ' + str(relative))
    data = path.read_bytes()
    if re.search(rb'\b(?:ghp_[A-Za-z0-9]{24,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9]{32,})|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', data):
        raise SystemExit('Credential-shaped content rejected in ' + str(relative))
    files.append((relative.as_posix(), data))
files.sort(key=lambda x: x[0])
manifest = {
    'product': 'Dynamic Stage X', 'package': 'com.tsangbaby.dynamicstagex',
    'version': '0.1.0-alpha1', 'kind': 'unbuilt source candidate',
    'excluded': ['raw public-header evidence cache', 'caches', 'binaries', 'original user reference assets'],
    'files': [{'path': name, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()} for name, data in files]
}
manifest_data = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode()
(ROOT / 'SOURCE-MANIFEST.json').write_bytes(manifest_data)
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in files:
        archive.writestr('DynamicStageX/' + name, data)
    archive.writestr('DynamicStageX/SOURCE-MANIFEST.json', manifest_data)
with zipfile.ZipFile(args.output) as archive:
    if archive.testzip() is not None or len(archive.namelist()) != len(files) + 1:
        raise SystemExit('Archive member/integrity validation failed')
    for name, data in files:
        if archive.read('DynamicStageX/' + name) != data:
            raise SystemExit('Archive byte mismatch: ' + name)
print(json.dumps({'output': str(args.output), 'files': len(files) + 1,
                  'bytes': args.output.stat().st_size,
                  'sha256': hashlib.sha256(args.output.read_bytes()).hexdigest(),
                  'every_file_matches': True}, ensure_ascii=False, indent=2))
