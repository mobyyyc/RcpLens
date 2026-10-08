#!/usr/bin/env python3
"""Collect explicitly selected fictional XCTest PNGs and source hashes. No normal/private receipt data."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--attachments', type=Path, required=True, help='xcresulttool export attachments output')
parser.add_argument('--log', type=Path, required=True)
parser.add_argument('--source-hashes', type=Path, help='Immutable source hash snapshot from the tested build')
parser.add_argument('--output', type=Path, default=Path('docs/evidence/t06-splitting'))
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
args.output.mkdir(parents=True, exist_ok=True)
manifest = json.loads((args.attachments / 'manifest.json').read_text())
images = []
counts = {}
for test in manifest:
    for attachment in test['attachments']:
        name = attachment['suggestedHumanReadableName']
        if name.startswith(('T06-', 'Tucked-wallet-', 'Elastic-wallet-', 'Elastic-stack-')) and attachment['exportedFileName'].endswith('.png'):
            label = name.split('_0_')[0]
            counts[label] = counts.get(label, 0) + 1
            suffix = '' if counts[label] == 1 else '-' + str(counts[label])
            destination = args.output / (label + suffix + '.png')
            shutil.copyfile(args.attachments / attachment['exportedFileName'], destination)
            images.append({'path': destination.name, 'test': test['testIdentifier'], 'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()})
files = sorted([*root.glob('RcpLens/**/*.swift'), *root.glob('RcpLensTests/*.swift'), *root.glob('RcpLensUITests/*.swift'), root / 'RcpLens.xcodeproj/project.pbxproj'])
live_hashes = {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
hashes = json.loads(args.source_hashes.read_text()) if args.source_hashes else live_hashes
drift = [path for path in sorted(set(hashes) | set(live_hashes)) if hashes.get(path) != live_hashes.get(path)]
log = args.log.read_text()
report = {
    'fictionalOnly': True,
    'sourceHashes': hashes,
    'sourceSnapshot': str(args.source_hashes.resolve()) if args.source_hashes else None,
    'workingTreeChangesSinceBuild': drift,
    'images': images,
    'testLog': str(args.log.resolve()),
    'testLogSHA256': hashlib.sha256(args.log.read_bytes()).hexdigest(),
    'contrastFindings': [json.loads(match) for match in re.findall(r'T06_CONTRAST_ISSUE (\{[^\n]+\})', log)],
    'structuralFindings': [json.loads(match) for match in re.findall(r'T06_STRUCTURE_ISSUE (\{[^\n]+\})', log)],
    'passedCases': re.findall(r"Test Case '([^']+)' passed", log),
    'failedCases': re.findall(r"Test Case '([^']+)' failed", log),
}
(args.output / 'capture-index.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
print(f'Copied {len(images)} fictional PNG attachments; indexed {len(hashes)} source hashes.')
