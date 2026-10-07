#!/usr/bin/env python3
"""Real SDK checks, fictional payloads; emits only whitelisted aggregate states."""
import json
import os
from pathlib import Path
import sys
from evaluate import worker, write_json, PRIVATE
os.umask(0o077)
binary=Path('/tmp/RcpLens-T03-worker')
probe=worker(binary,{'operation':'probe'})
checks={}
checks['forced_unavailable']=worker(binary,{'operation':'text','text':'SYNTHETIC TOTAL 1.00','forceUnavailable':True})['status']=='forced_unavailable'
checks['malformed_image']=worker(binary,{'operation':'ocr','image':str(PRIVATE/'evaluation'/'does-not-exist.png')})['status']=='operation_failed'
context=worker(binary,{'operation':'context_probe','text':'\n'.join(f'SYNTHETIC ITEM {i} 1.00' for i in range(6000))})
checks['context_limit_rejected']=context['status'] in ('context_preflight_rejected','context_exceeded')
result={'environment':probe,'checks':checks,'context_status':context['status'],'all_passed':all(checks.values())}
write_json(PRIVATE/'evaluation'/'runtime-checks.json',result)
print(json.dumps(result,indent=2))
sys.exit(0 if all(checks.values()) else 1)
