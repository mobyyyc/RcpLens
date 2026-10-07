#!/usr/bin/env python3
"""Research-only raw factual scores against human/synthetic references, without source acceptance."""
import argparse
import collections
import json
import os
from pathlib import Path
import sys
from evaluate import within_private, summary, validate_expected, cents, empty_receipt, score, write_json, FIELDS, KINDS

def normalize_raw(proposal):
    result=empty_receipt()
    if not isinstance(proposal,dict):return result
    def value(c,money=False):
        if not isinstance(c,dict) or not isinstance(c.get('value'),str) or not c['value']:return None
        if money:
            try:return cents(c['value'])
            except ValueError:return None
        return c['value']
    for f in FIELDS:result[f]=value(proposal.get(f),f in ('subtotal','total'))
    lines=proposal.get('lines')
    if isinstance(lines,list):
        for line in lines:
            if not isinstance(line,dict):continue
            result['lines'].append({'kind':line.get('kind') if isinstance(line.get('kind'),str) else 'unknown',
                                   'description':value(line.get('description')) or '',
                                   'amount':value(line.get('amount'),True),'quantity':value(line.get('quantity'))})
    return result

def main():
    os.umask(0o077)
    ap=argparse.ArgumentParser();ap.add_argument('--run',type=Path,required=True);ap.add_argument('--labels',type=Path,required=True);args=ap.parse_args()
    try:
        run=within_private(args.run);label_doc=json.loads(within_private(args.labels).read_text())
        accepted=summary(run,args.labels) # Same verification/identity/schema gate as accepted scores.
        manifest=json.loads((run/'manifest.json').read_text());expected={}
        for label in label_doc['receipts']:
            if label.get('reviewed') is not True or label.get('verification_method')!='human_against_original':continue
            if manifest['corpus_kind']=='private_real' and label.get('verification_checks')!={'fields':True,'items':True,'amounts':True,'adjustments':True}:continue
            match=next((r for r in manifest['receipts'] if r['id']==label['id'] and r['sha256']==label['sha256']),None)
            if match:expected[label['id']]=validate_expected(label['expected'])
        output={'basis':'raw proposals compared with checked references; not source-accepted output',
                'corpus_kind':manifest['corpus_kind'],'references_scored':len(expected),'approaches':{}}
        for approach in ('B','C'):
            counts=collections.Counter();statuses=collections.Counter();losses=collections.Counter()
            for rid,label in expected.items():
                path=run/'raw-model'/f'{rid}-{approach}.json'
                if not path.exists():continue
                raw=json.loads(path.read_text());statuses[raw['status']]+=1
                proposed=normalize_raw(raw.get('receipt')) if raw['status']=='ok' else empty_receipt()
                raw_score=score(proposed,label);counts.update(raw_score)
                accepted_receipt=json.loads((run/'results'/path.name).read_text())['receipt']
                for f in FIELDS:
                    if proposed[f] is not None and accepted_receipt[f] is None:losses[f+'_source_rejected']+=1
            metrics=dict(counts)
            for f in FIELDS:metrics[f+'_accuracy']=counts[f+'_correct']/counts[f+'_expected'] if counts[f+'_expected'] else None
            metrics['item_amount_accuracy']=counts['item_amounts_correct']/counts['items_expected'] if counts['items_expected'] else None
            metrics['line_amount_accuracy']=counts['line_amounts_correct']/counts['lines_expected'] if counts['lines_expected'] else None
            output['approaches'][approach]={'statuses':dict(statuses),'metrics':metrics,'source_field_rejections':dict(losses)}
        write_json(run/'raw-factual-aggregate.json',output)
        print(json.dumps(output,indent=2)) # Explicit aggregate only.
    except Exception:
        print('raw_scoring_failed; private error suppressed',file=sys.stderr);return 1
    return 0
if __name__=='__main__':sys.exit(main())
