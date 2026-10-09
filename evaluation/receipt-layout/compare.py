#!/usr/bin/env python3
"""Local comparison. Only aggregate counters may reach stdout or public files."""
import argparse
import collections
import json
import os
from pathlib import Path
import platform
import statistics
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'evaluation/receipt-audit'))
import audit as a

MODES = ('baseline', 'text-association', 'text-column-association', 'document-lines', 'document-tables', 'document-association')
SOURCES = tuple(sorted(str(p.relative_to(ROOT)) for folder in ('Sliplet', 'evaluation/receipt-layout', 'evaluation/receipt-audit', 'evaluation/receipt-eval')
                       for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in {'.swift', '.py', '.sh'}))

def verify_membership(response):
    source = [o['id'] for o in response['observations']]
    grouped = [i for row in response['groupedRowIDs'] for i in row]
    if len(source) != len(set(source)) or collections.Counter(source) != collections.Counter(grouped):
        raise ValueError('observation_conservation_failed')
    valid = set(source)
    parsed = response['parsed']
    ids = [i for line in parsed['lines'] for i in line['sourceLineIDs']]
    ids += [i for issue in parsed['issues'] for i in issue['sourceLineIDs']]
    if not set(ids) <= valid: raise ValueError('provenance_failed')
    for observation in response['observations']:
        b = observation.get('boundingBox')
        if b is not None and not (0 <= b['x'] <= 1 and 0 <= b['y'] <= 1 and
                                  b['width'] > 0 and b['height'] > 0 and
                                  b['x']+b['width'] <= 1.00000001 and b['y']+b['height'] <= 1.00000001):
            raise ValueError('source_coordinate_failed')

def record(response, expected, store):
    actual = a.normalize(response)
    details, _ = a.diagnose(actual, expected, response['observations'])
    return dict(store=store, score=dict(a.amount_score(actual, expected)), receipt=actual,
                expected=expected, failure_details=details, wall_ms=response['processWallMS'],
                **{name: response[name] for name in ('decodeMS', 'ocrMS', 'parserMS')})

def full_parsed(response):
    parsed = json.loads(json.dumps(response['parsed']))
    for line in parsed['lines']:
        line.pop('id', None)
        line.pop('sourceLineIDs', None)
    for issue in parsed['issues']: issue.pop('sourceLineIDs', None)
    return parsed

def validated_labels(label_path, archived, groups):
    checked = a.labels_for(json.loads((archived/'manifest.json').read_text()), json.loads(label_path.read_text()))
    if set(checked) != {g['purchase_id'] for g in groups}: raise ValueError('baseline_label_ids_mismatch')
    entries = {r['id']:r for r in json.loads(label_path.read_text())['receipts']}
    for group in groups:
        if entries[group['purchase_id']]['sha256'] != group['images'][0]['sha256'] or a.store_for(checked[group['purchase_id']]) != group['store']:
            raise ValueError('baseline_label_input_mismatch')
    return checked

def fingerprints(baseline, label_path):
    groups = json.loads((baseline/'corpus.json').read_text())['groups']
    return dict(sources={name: a.e.input_digest(ROOT/name) for name in SOURCES},
                project=a.e.input_digest(ROOT/'Sliplet.xcodeproj/project.pbxproj'),
                originals={g['purchase_id']: a.e.input_digest(Path(g['images'][0]['path'])) for g in groups},
                references=a.e.input_digest(label_path),
                baseline={str(p.relative_to(baseline)): a.e.input_digest(p) for p in baseline.rglob('*') if p.is_file()})

def run(args):
    os.umask(0o077)
    output, baseline = a.private(args.run), a.private(args.baseline)
    if output.exists(): raise ValueError('new_run_required')
    groups = json.loads((baseline/'corpus.json').read_text())['groups']
    if a.validate_groups(groups) != {'development': 5}: raise ValueError('unexpected_corpus')
    label_path, archived = a.private(args.labels), a.private(args.archived)
    checked = validated_labels(label_path, archived, groups)
    before = fingerprints(baseline, label_path)
    output.mkdir(parents=True, mode=0o700)
    a.e.write_json(output/'manifest.json', dict(fingerprints=before, groups=groups, modes=MODES, labels=str(label_path), archived=str(archived),
                 worker_sha256=a.e.input_digest(Path(args.worker)), parser_adapter_sha256=a.e.input_digest(Path('/tmp/Sliplet-P2-02-Parsing.swift'))))
    records = {mode: [] for mode in MODES}
    repeats = collections.Counter()
    membership = collections.Counter()
    structure = collections.Counter()
    languages = set()
    selected_languages = set()
    # Rotate variant order by purchase; framework caches remain uncontrolled.
    for index, group in enumerate(groups):
        offset = index % len(MODES)
        modes = MODES[offset:] + MODES[:offset]
        for mode in modes:
            for repeat in range(2):
                response = a.capture_worker(args.worker, dict(image=group['images'][0]['path'], mode=mode))
                verify_membership(response)
                membership[mode] += 1
                a.e.write_json(output/mode/(group['purchase_id']+f'-pass{repeat+1}.json'), response)
                if repeat == 0:
                    first = response
                    records[mode].append(record(response, checked[group['purchase_id']], group['store']))
                    if mode == 'document-lines':
                        structure['documents'] += len(response['documents'])
                        structure['native_table_rows'] += len(response['tableRowIDs'])
                        languages.update(response['supportedLanguages'])
                else:
                    repeats[mode] += int(full_parsed(first) == full_parsed(response))
            if mode == 'document-tables':
                structure['table_membership_valid_receipts'] += int(first['tableMembershipValid'])
                structure['table_rows_applied'] += first['tableRowsApplied']
                structure[first.get('tableFallbackReason') or 'native_membership_used'] += 1
            if mode == 'document-lines': selected_languages.update(first['selectedLanguages'])
            print(json.dumps(dict(status='captured', variant=mode, completed_purchases=index+1)), flush=True)
    # Full parser baseline equality, excluding generated evidence/line UUIDs.
    baseline_equal = 0
    for group in groups:
        old = json.loads((baseline/'current'/(group['purchase_id']+'-pass1.json')).read_text())
        new = json.loads((output/'baseline'/(group['purchase_id']+'-pass1.json')).read_text())
        baseline_equal += int(full_parsed(old) == full_parsed(new))
    if before != fingerprints(baseline, label_path): raise ValueError('preservation_failed')
    aggregate = dict(schema_version=1, corpus=dict(development=5, held_out=0),
                     baseline_equal=baseline_equal, repeats_equal=dict(repeats),
                     membership_checks=dict(membership), document_structure=dict(structure),
                     supported_document_languages=sorted(languages),
                     selected_document_languages=sorted(selected_languages),
                     environment=dict(system=platform.system(), os=platform.mac_ver()[0], machine=platform.machine()),
                     variants={mode:a.aggregate(records[mode]) for mode in MODES},
                     source_sha256=before['sources'], preservation=dict(originals=True, references=True, baseline=True, signing_project=True, sources=True),
                     limitations=['exposed development only', 'Mac process-wall timing', 'phone latency and timed human corrections unmeasured', 'quantity/unit accuracy unscored'])
    a.e.write_json(output/'aggregate.json', aggregate)
    a.e.write_json(output/'private-scores.json', records)
    print(json.dumps(dict(status='complete', variants=len(MODES), purchases=5, requests=len(MODES)*10)))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True)
    parser.add_argument('--baseline', default=str(ROOT/'private-receipts/evaluation/p2-01-final'))
    parser.add_argument('--labels', default=str(ROOT/'private-receipts/evaluation/real-v1/ground-truth.json'))
    parser.add_argument('--archived', default=str(ROOT/'private-receipts/evaluation/real-final'))
    parser.add_argument('--worker', type=Path, default=Path('/tmp/Sliplet-P2-02-worker'))
    args = parser.parse_args()
    try: run(args)
    except Exception: print('{"status":"failed_private_details_suppressed"}'); sys.exit(1)
