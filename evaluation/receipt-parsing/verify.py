#!/usr/bin/env python3
"""Read-only rescore and source/preservation verification; never print private values."""
import argparse
import json
from pathlib import Path
import sys
import compare as c

def verify(run):
    run=c.a.private(run);manifest=json.loads((run/'manifest.json').read_text());groups=manifest['groups']
    baseline=Path(manifest['baseline']);labels=Path(manifest['labels'])
    checked=c.layout.validated_labels(labels,Path(manifest['archived']),groups)
    if c.a.validate_groups(groups)!={'development':5}:raise ValueError('corpus')
    if c.fingerprints(baseline,labels,groups)!=manifest['fingerprints']:raise ValueError('preservation')
    for mode,digest in manifest['worker_sha256'].items():
        if c.a.e.input_digest(Path('/tmp/Sliplet-P2-03-'+mode+'-worker'))!=digest:raise ValueError('worker_changed')
    if c.a.e.input_digest(Path('/tmp/Sliplet-P2-03-before-Parsing.swift'))!=manifest['before_parser_sha256']:raise ValueError('before_parser_changed')
    records={m:[] for m in ('frozen-before','frozen-after','fresh-after')};repeats=frozen_equal=baseline_equal=fresh_ocr_equal=0
    for g in groups:
        rid=g['purchase_id'];responses={}
        accepted=json.loads((baseline/'current'/(rid+'-pass1.json')).read_text())
        for mode in records:
            name=rid+('-pass1.json' if mode=='fresh-after' else '.json')
            response=json.loads((run/mode/name).read_text());c.membership(response);responses[mode]=response
            if mode!='fresh-after' and response['observations']!=accepted['observations']:raise ValueError('frozen_source')
            records[mode].append(c.layout.record(response,checked[rid],g['store']))
        baseline_equal+=int(c.layout.full_parsed(responses['frozen-before'])==c.layout.full_parsed(accepted))
        frozen_equal+=int(c.layout.full_parsed(responses['frozen-after'])==c.layout.full_parsed(responses['fresh-after']))
        second=json.loads((run/'fresh-after'/(rid+'-pass2.json')).read_text());c.membership(second)
        repeats+=int(c.layout.full_parsed(second)==c.layout.full_parsed(responses['fresh-after']))
        def raw(r):return [{k:v for k,v in o.items() if k!='id'} for o in r['observations']]
        fresh_ocr_equal+=int(raw(responses['fresh-after'])==raw(accepted))
    expected=c.public_report(records,manifest,repeats,frozen_equal,baseline_equal,fresh_ocr_equal)
    if expected!=json.loads((run/'aggregate.json').read_text()):raise ValueError('aggregate_mismatch')
    if records!=json.loads((run/'private-scores.json').read_text()):raise ValueError('private_scores_mismatch')
    if (repeats,frozen_equal,baseline_equal)!=(5,5,5):raise ValueError('repeat_or_baseline')
    print('{"status":"verified","purchases":5,"requests":20,"held_out":0}')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--run',required=True)
    try:verify(parser.parse_args().run)
    except Exception:print('{"status":"verification_failed_private_details_suppressed"}');sys.exit(1)
