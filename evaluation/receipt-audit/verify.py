#!/usr/bin/env python3
"""Read-only independent rescoring of captured P2-01 evidence. No inference."""
import argparse
import collections
import json
from pathlib import Path
import sys
import audit as a

def verify(run, archived, labels):
    run, archived, labels = a.private(run), a.private(archived), a.private(labels)
    report = json.loads((run/'aggregate.json').read_text())
    manifest = json.loads((run/'manifest.json').read_text())
    corpus = json.loads((run/'corpus.json').read_text())
    groups = corpus['groups']
    if a.validate_groups(groups) != report['corpus_splits']: raise ValueError('split_mismatch')
    expected = a.labels_for(json.loads((archived/'manifest.json').read_text()), json.loads(labels.read_text()))
    if len(groups) != len(expected): raise ValueError('corpus_mismatch')
    for name, digest in report['source_sha256'].items():
        if a.e.input_digest(a.ROOT/name) != digest: raise ValueError('source_mismatch')
    if report['source_sha256'] != manifest['source_sha256']: raise ValueError('source_manifest_mismatch')
    for name, digest in manifest['archived_file_sha256'].items():
        if a.e.input_digest(archived/name) != digest: raise ValueError('archive_changed')
    if a.e.input_digest(a.ROOT/'Sliplet.xcodeproj/project.pbxproj') != manifest['signing_project_sha256']:
        raise ValueError('signing_project_changed')
    counts = {store: collections.Counter() for store in ('all',)+a.STORES}
    equals = 0
    for group in groups:
        rid = group['purchase_id']
        if group['store'] != a.store_for(expected[rid]): raise ValueError('store_mismatch')
        for image in group['images']:
            if a.e.input_digest(a.private(image['path'])) != image['sha256']: raise ValueError('original_changed')
        first = json.loads((run/'current'/f'{rid}-pass1.json').read_text())
        second = json.loads((run/'current'/f'{rid}-pass2.json').read_text())
        if first['status'] != 'ok' or second['status'] != 'ok': raise ValueError('failed_pass')
        actual = a.normalize(first)
        score = a.amount_score(actual, expected[rid])
        for store in ('all', group['store']): counts[store].update(score)
        details = json.loads((run/'scores'/f'{rid}.json').read_text())
        if dict(score) != details['score'] or actual != details['receipt']: raise ValueError('score_mismatch')
        failures, extras = a.diagnose(actual, expected[rid], first['observations'])
        if failures != details['failure_details'] or extras != details['extra_actual_line_indices']:
            raise ValueError('failure_evidence_mismatch')
        equals += int(a.stable_response(first) == a.stable_response(second))
    for store, counter in counts.items():
        for key, value in counter.items():
            if value != report['production_swift_fresh_ocr'][store]['counts'].get(key, 0): raise ValueError('aggregate_mismatch')
    if equals != report['equal_successful_repeat_pairs']: raise ValueError('repeat_mismatch')
    historical = report['historical_python_reproduction']['all']['counts']
    if {k:historical[k] for k in ('items_expected','item_amounts_correct','total_correct','omitted_lines','invented_lines','correction_operations')} != dict(items_expected=66,item_amounts_correct=57,total_correct=2,omitted_lines=12,invented_lines=1,correction_operations=20):
        raise ValueError('pilot_reproduction_mismatch')
    print('verified: source/archive/original/signing hashes, purchase separation, five checked scores and repeat pairs')

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--run', required=True, type=Path)
    p.add_argument('--archived', default=a.e.PRIVATE/'evaluation/real-final', type=Path)
    p.add_argument('--labels', default=a.e.PRIVATE/'evaluation/real-v1/ground-truth.json', type=Path)
    args = p.parse_args()
    try: verify(args.run,args.archived,args.labels)
    except Exception:
        print('verification_failed; private diagnostic suppressed', file=sys.stderr); sys.exit(1)
