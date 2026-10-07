#!/usr/bin/env python3
"""Apply final deterministic normalization to saved private evidence, without rerunning AI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
from evaluate import within_private, group_rows, parse, validate_proposal, empty_receipt, write_json, summary, VERSION

def main():
    os.umask(0o077)
    ap=argparse.ArgumentParser();ap.add_argument('--run',type=Path,required=True);ap.add_argument('--labels',type=Path);args=ap.parse_args()
    try:
        run=within_private(args.run)
        manifest=json.loads((run/'manifest.json').read_text())
        before=run/'results-before-final-validation'
        before.mkdir(exist_ok=True,mode=0o700)
        source=Path(__file__).with_name('evaluate.py')
        source_hash=hashlib.sha256(source.read_bytes()).hexdigest()
        count=0
        for entry in manifest['receipts']:
            rid=entry['id']
            ocr=json.loads((run/'ocr'/f'{rid}.json').read_text())
            for approach in ('A','B','C'):
                for suffix in ('','-repeat'):
                    path=run/'results'/f'{rid}-{approach}{suffix}.json'
                    if not path.exists():continue
                    dest=before/path.name
                    if not dest.exists():shutil.copy2(path,dest)
                    result=json.loads(path.read_text())
                    if approach=='A':
                        raw=json.loads((run/'ocr'/f'{rid}-repeat.json').read_text()) if suffix else ocr['raw']
                        result['receipt']=parse(group_rows(raw.get('observations',[])))
                    else:
                        raw=json.loads((run/'raw-model'/path.name).read_text())
                        result['receipt']=validate_proposal(raw.get('receipt'),ocr['rows']) if raw['status']=='ok' else empty_receipt()
                        result['proposed_line_count']=len(raw.get('receipt',{}).get('lines',[]))
                    result['parser_version']=VERSION
                    result['validation_source_sha256']=source_hash
                    write_json(path,result);count+=1
        manifest.setdefault('configuration',{}).update({'final_validation_version':VERSION,'final_validation_source_sha256':source_hash})
        write_json(run/'manifest.json',manifest)
        summary(run,args.labels)
        print(f'final normalization applied to {count} saved results; private raw evidence unchanged')
    except Exception:
        print('revalidation_failed; private error suppressed',file=sys.stderr);return 1
    return 0
if __name__=='__main__':sys.exit(main())
