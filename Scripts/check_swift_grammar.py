#!/usr/bin/env python3
"""Tree-sitter grammar check ONLY: not Swift typechecking, UIKit compilation or device proof."""
from pathlib import Path
import argparse
import json
import sys
import tree_sitter
import tree_sitter_swift

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--output', type=Path)
args = parser.parse_args()
language = tree_sitter.Language(tree_sitter_swift.language())
reader = tree_sitter.Parser(language)
files = sorted(args.root.glob('Sources/*/*.swift')) + sorted(args.root.glob('Preferences/*.swift'))
files += sorted(args.root.glob('Tests/*/*.swift')) + [args.root / 'Package.swift']
errors = []
for path in files:
    data = path.read_bytes()
    tree = reader.parse(data)
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type == 'ERROR' or node.is_missing:
            errors.append({'file': str(path.relative_to(args.root)), 'type': node.type,
                           'line': node.start_point.row + 1, 'column': node.start_point.column + 1,
                           'snippet': data[node.start_byte:node.end_byte].decode('utf8', 'replace')[:180]})
        stack.extend(reversed(node.children))
report = {'scope': 'tree-sitter Swift grammar only; not compilation or semantic validation',
          'files': len(files), 'errors': errors, 'passed': not errors}
text = json.dumps(report, ensure_ascii=False, indent=2)
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(text + '\n')
print(text)
sys.exit(bool(errors))
