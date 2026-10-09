#!/usr/bin/env python3
"""Read-only verification and rescore of captured P2-02 results. No inference."""
import argparse
import collections
import json
from pathlib import Path
import sys
import compare as c

def verify(output, baseline):
    output, baseline = c.a.private(output), c.a.private(baseline)
    manifest = json.loads((output/'manifest.json').read_text())
    report = json.loads((output/'aggregate.json').read_text())
    labels = c.a.private(manifest['labels'])
    expected = c.validated_labels(labels, c.a.private(manifest['archived']), manifest['groups'])
    if manifest['fingerprints'] != c.fingerprints(baseline, labels): raise ValueError('fingerprint_mismatch')
    if report['source_sha256'] != manifest['fingerprints']['sources']: raise ValueError('public_source_mismatch')
    if c.a.validate_groups(manifest['groups']) != {'development':5}: raise ValueError('corpus_mismatch')
    baseline_equal = 0
    membership, repeats, structure = collections.Counter(), collections.Counter(), collections.Counter()
    languages, selected = set(), set()
    saved_scores = json.loads((output/'private-scores.json').read_text())
    for mode in c.MODES:
        records = []
        for group in manifest['groups']:
            rid = group['purchase_id']
            first = json.loads((output/mode/(rid+'-pass1.json')).read_text())
            second = json.loads((output/mode/(rid+'-pass2.json')).read_text())
            for response in (first, second):
                if response['status'] != 'ok' or response['mode'] != mode: raise ValueError('request_mismatch')
                c.verify_membership(response)
                membership[mode] += 1
            repeats[mode] += int(c.full_parsed(first) == c.full_parsed(second))
            records.append(c.record(first, expected[rid], group['store']))
            if mode == 'baseline':
                old = json.loads((baseline/'current'/(rid+'-pass1.json')).read_text())
                baseline_equal += int(c.full_parsed(old) == c.full_parsed(first))
            if mode == 'document-lines':
                structure['documents'] += len(first['documents'])
                structure['native_table_rows'] += len(first['tableRowIDs'])
                languages.update(first['supportedLanguages']); selected.update(first['selectedLanguages'])
            if mode == 'document-tables':
                source = {o['id'] for o in first['observations']}
                ids = [i for row in first['tableRowIDs'] for i in row]
                valid = len(ids)==len(set(ids)) and set(ids) <= source
                if first['tableMembershipValid'] != valid: raise ValueError('table_membership_mismatch')
                if first['tableRowsApplied'] != (len(first['tableRowIDs']) if valid else 0): raise ValueError('table_applied_mismatch')
                structure['table_membership_valid_receipts'] += int(valid)
                structure['table_rows_applied'] += first['tableRowsApplied']
                structure[first.get('tableFallbackReason') or 'native_membership_used'] += 1
        # The capture order rotates, so normalize order for private-record equality.
        key = lambda r: json.dumps(r['expected'], sort_keys=True)
        if sorted(records, key=key) != sorted(saved_scores[mode], key=key): raise ValueError('private_score_mismatch')
        if c.a.aggregate(records) != report['variants'][mode]: raise ValueError('aggregate_mismatch')
    if baseline_equal != report['baseline_equal'] or dict(membership) != report['membership_checks'] or dict(repeats) != report['repeats_equal']:
        raise ValueError('repeat_or_membership_mismatch')
    if dict(structure) != report['document_structure'] or sorted(languages) != report['supported_document_languages'] or sorted(selected) != report['selected_document_languages']:
        raise ValueError('document_metadata_mismatch')
    print('verified: six variants, 60 captured requests, checked labels, full parsed repeats, source membership, scores and preservation fingerprints')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--run', required=True)
    parser.add_argument('--baseline', default=str(c.ROOT/'private-receipts/evaluation/p2-01-final'))
    args = parser.parse_args()
    try: verify(args.run, args.baseline)
    except Exception: print('verification_failed; private details suppressed'); sys.exit(1)
