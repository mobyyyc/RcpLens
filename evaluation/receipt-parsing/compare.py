#!/usr/bin/env python3
"""Local P2-03 replay and recapture. Stdout is safe counters/status only."""
import argparse
import collections
import json
import os
import importlib.util
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'evaluation/receipt-audit'))
import audit as a
layout_spec = importlib.util.spec_from_file_location('receipt_layout_compare', ROOT/'evaluation/receipt-layout/compare.py')
layout = importlib.util.module_from_spec(layout_spec)
layout_spec.loader.exec_module(layout)

SOURCE_FOLDERS = ('Sliplet', 'SlipletTests', 'evaluation/receipt-parsing')

def source_hashes():
    return {str(p.relative_to(ROOT)):a.e.input_digest(p) for folder in SOURCE_FOLDERS
            for p in sorted((ROOT/folder).rglob('*')) if p.is_file() and p.suffix in {'.swift','.py','.sh'}}

def fingerprints(baseline, labels, groups):
    return dict(sources=source_hashes(), signing_project=a.e.input_digest(ROOT/'Sliplet.xcodeproj/project.pbxproj'),
                references=a.e.input_digest(labels),
                originals={g['purchase_id']:a.e.input_digest(Path(g['images'][0]['path'])) for g in groups},
                accepted_evidence={name:{str(p.relative_to(ROOT/'private-receipts/evaluation'/name)):a.e.input_digest(p)
                                        for p in (ROOT/'private-receipts/evaluation'/name).rglob('*') if p.is_file()}
                                   for name in ('real-final','p2-01-final','p2-02-final')})

def membership(response):
    layout.verify_membership(response)
    raw = [o['id'] for o in response['observations']]
    interpreted = [i for row in response['interpretedRowIDs'] for i in row]
    if collections.Counter(raw) != collections.Counter(interpreted): raise ValueError('interpretation_conservation')
    for line in response['parsed']['lines']:
        if len(line['sourceLineIDs']) != len(set(line['sourceLineIDs'])): raise ValueError('duplicate_line_source')
    issues = response['parsed']['issues']
    if not any(i['code']=='source_review_required' and i['sourceLineIDs']==raw for i in issues):
        raise ValueError('source_review_conservation')

def public_report(records, manifest, repeats, frozen_equal, baseline_equal, fresh_ocr_equal):
    return dict(schema_version=1, task='P2-03', corpus=dict(development=5, held_out=0),
                variants={k:a.aggregate(v) for k,v in records.items()},
                baseline_full_parsed_equal=baseline_equal, fresh_full_parsed_repeat_equal=repeats,
                after_frozen_fresh_full_parsed_equal=frozen_equal, unchanged_fresh_ocr_equal=fresh_ocr_equal,
                successful_requests=20, source_sha256=manifest['fingerprints']['sources'],
                worker_sha256=manifest['worker_sha256'], before_parser_sha256=manifest['before_parser_sha256'],
                accepted_baseline_commit='1e5680b',
                environment=dict(system=platform.system(), os=platform.mac_ver()[0], machine=platform.machine()),
                preservation=dict(originals=True, checked_references=True, accepted_evidence=True, signing_project=True, sources_during_capture=True),
                limitations=['Five exposed development purchases; zero held-out purchases.',
                             'Quantity/unit accuracy and human correction time unscored.',
                             'Omission/extra counters are description-matched proxies, not adjudicated invention.',
                             'Mac process-wall and parser timings; phone latency and correction time pending.',
                             'No receipt automatically confirmed by reconciliation.'])

def run(args):
    os.umask(0o077)
    output = a.private(args.run); baseline = ROOT/'private-receipts/evaluation/p2-01-final'
    labels = ROOT/'private-receipts/evaluation/real-v1/ground-truth.json'; archive = ROOT/'private-receipts/evaluation/real-final'
    if output.exists(): raise ValueError('new_run_required')
    groups = json.loads((baseline/'corpus.json').read_text())['groups']
    if a.validate_groups(groups) != {'development':5}: raise ValueError('unexpected_corpus')
    checked = layout.validated_labels(labels, archive, groups)
    before = fingerprints(baseline, labels, groups)
    binaries = {m:Path('/tmp/Sliplet-P2-03-'+m+'-worker') for m in ('before','after')}
    manifest = dict(fingerprints=before, groups=groups, labels=str(labels), baseline=str(baseline), archived=str(archive),
                    worker_sha256={m:a.e.input_digest(p) for m,p in binaries.items()},
                    before_parser_sha256=a.e.input_digest(Path('/tmp/Sliplet-P2-03-before-Parsing.swift')))
    output.mkdir(parents=True,mode=0o700); a.e.write_json(output/'manifest.json',manifest)
    records = {m:[] for m in ('frozen-before','frozen-after','fresh-after')}
    repeats=frozen_equal=baseline_equal=fresh_ocr_equal=0
    for group in groups:
        rid=group['purchase_id'];expected=checked[rid];store=group['store']
        accepted=json.loads((baseline/'current'/(rid+'-pass1.json')).read_text())
        for m in ('before','after'):
            response=a.capture_worker(binaries[m],dict(observations=accepted['observations']))
            if response['observations']!=accepted['observations']:raise ValueError('frozen_observations_changed')
            membership(response);a.e.write_json(output/('frozen-'+m)/(rid+'.json'),response)
            records['frozen-'+m].append(layout.record(response,expected,store))
            if m=='before':baseline_equal+=int(layout.full_parsed(response)==layout.full_parsed(accepted))
            else:frozen=response
        for repeat in range(2):
            response=a.capture_worker(binaries['after'],dict(image=group['images'][0]['path']))
            membership(response);a.e.write_json(output/'fresh-after'/(rid+f'-pass{repeat+1}.json'),response)
            if repeat==0:
                first=response;records['fresh-after'].append(layout.record(response,expected,store))
                frozen_equal+=int(layout.full_parsed(frozen)==layout.full_parsed(response))
                def raw(r):return [{k:v for k,v in o.items() if k!='id'} for o in r['observations']]
                fresh_ocr_equal+=int(raw(response)==raw(accepted))
            else:repeats+=int(layout.full_parsed(first)==layout.full_parsed(response))
    if before!=fingerprints(baseline,labels,groups):raise ValueError('preservation_failed')
    if baseline_equal!=5 or repeats!=5 or frozen_equal!=5:raise ValueError('comparison_or_repeat_failed')
    report=public_report(records,manifest,repeats,frozen_equal,baseline_equal,fresh_ocr_equal)
    a.e.write_json(output/'private-scores.json',records);a.e.write_json(output/'aggregate.json',report)
    print(json.dumps(dict(status='complete', purchases=5, requests=20, held_out=0)))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--run',required=True)
    try:run(parser.parse_args())
    except Exception:print('{"status":"failed_private_details_suppressed"}');sys.exit(1)
