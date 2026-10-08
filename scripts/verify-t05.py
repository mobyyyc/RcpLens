#!/usr/bin/env python3
"""Local simulator verification. Private data, logs and screenshots never reach stdout.
No raw OCR, amounts, receipt identifiers, hashes, label text or filenames are printed.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import datetime

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / 'private-receipts'
EVIDENCE = ROOT / 'docs/evidence/t05'
SIMULATOR = '50661E83-1F58-466B-99F0-9DC517D8EC82'
ENV = {**os.environ, 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}


def command(args, logfile=None, env=ENV):
    result = subprocess.run(args, env=env, capture_output=True)
    if logfile:
        logfile.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        logfile.write_bytes(result.stdout + result.stderr)
        logfile.chmod(0o600)
    if result.returncode:
        raise ValueError('local_command_failed')
    return result.stdout.decode().strip()


def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_text(json.dumps(obj, indent=2) + '\n'); path.chmod(0o600)


def prepare(private=True):
    command(['xcrun', 'simctl', 'install', SIMULATOR, '/tmp/RcpLens-T05-DerivedData/Build/Products/Debug-iphonesimulator/RcpLens.app'])
    container = Path(command(['xcrun', 'simctl', 'get_app_container', SIMULATOR, 'com.mobyyyc.RcpLens', 'data']))
    inbox = container / 'Documents/T05TestInbox'
    if private and inbox.exists(): shutil.rmtree(inbox)
    test_store = container / 'Library/Application Support/T05WorkflowTestStore'
    if test_store.exists(): shutil.rmtree(test_store)
    if private:
        manifest = json.loads((PRIVATE / 'evaluation/real-final/manifest.json').read_text())
        labels = json.loads((PRIVATE / 'evaluation/real-v1/ground-truth.json').read_text())
        references = {entry['id']: entry for entry in labels['receipts']}
        count = 0
        for slot, entry in enumerate(manifest['receipts']):
            image = Path(entry['image']).resolve()
            if not image.is_relative_to(PRIVATE.resolve()): raise ValueError('private_path_required')
            reference = references[entry['id']]
            if entry['sha256'] != reference['sha256'] or hashlib.sha256(image.read_bytes()).hexdigest() != entry['sha256']:
                raise ValueError('source_changed')
            if not reference['reviewed'] or reference.get('verification_method') != 'human_against_original': raise ValueError('human_reference_required')
            dest = inbox / f'slot{slot}'; dest.mkdir(parents=True, exist_ok=True, mode=0o700)
            shutil.copyfile(image, dest / 'source.heic'); (dest / 'source.heic').chmod(0o600)
            expected = reference['expected'].copy()
            # Normalize only the reference civil-date spelling, never fill unknowns.
            if expected.get('date'):
                for fmt in ('%Y-%m-%d', '%Y/%m/%d', '%m/%d/%Y', '%m/%d/%y', '%d-%b-%Y', '%b %d %Y'):
                    try: expected['date'] = datetime.datetime.strptime(expected['date'], fmt).date().isoformat(); break
                    except ValueError: pass
            write(dest / 'request.json', {'image': 'source.heic', 'expected': expected})
            count += 1
        if count != 5: raise ValueError('unexpected_corpus_count')
    dest = inbox / 'slot5'; dest.mkdir(parents=True, exist_ok=True, mode=0o700)
    shutil.copyfile(ROOT / 'RcpLens/Resources/synthetic-receipt.png', dest / 'source.png')
    write(dest / 'request.json', {'image': 'source.png', 'expected': {'merchant': 'FICTIONAL SHOP', 'date': '2026-10-07',
        'subtotal': 1234, 'total': 1234, 'lines': [{'kind':'purchase','description':'FICTIONAL ITEM','amount':1234,'quantity':'1'}]}})
    print(json.dumps({'status':'prepared','private_sources_verified':count if private else 0,'synthetic_sources':1}))


def run(private, accessibility=False):
    run = PRIVATE / 'evaluation/t05' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    run.mkdir(parents=True, mode=0o700)
    container = Path(command(['xcrun','simctl','get_app_container',SIMULATOR,'com.mobyyyc.RcpLens','data']))
    for path in (container/'Documents/T05TestInbox').glob('*/report.json'): path.unlink()
    target = 'RcpLensUITests/LocalReceiptWorkflowTests' if private else ('RcpLensUITests/NativeAccessibilityTests' if accessibility else 'RcpLensUITests/SyntheticUIWorkflowTests')
    env = {**ENV, 'TEST_RUNNER_RCPLENS_T05_PRIVATE': 'YES' if private else 'NO'}
    source_files = list((ROOT/'RcpLens').rglob('*.swift')) + list((ROOT/'RcpLensUITests').rglob('*.swift')) + [ROOT/'RcpLens.xcodeproj/project.pbxproj']
    write(run/'source-hashes.json',{str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(source_files)})
    result = subprocess.run(['xcodebuild','-project','RcpLens.xcodeproj','-scheme','T05Workflow','-configuration','Debug',
        '-destination',f'platform=iOS Simulator,id={SIMULATOR}','-derivedDataPath','/tmp/RcpLens-T05-DerivedData',
        '-resultBundlePath',str(run/'tests.xcresult'),'-parallel-testing-enabled','NO',
        '-only-testing:'+target,'CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','test'], env=env,capture_output=True,cwd=ROOT)
    (run/'test.log').write_bytes(result.stdout + result.stderr); (run/'test.log').chmod(0o600)
    summary = subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(run/'tests.xcresult'),'--format','json'],env=ENV,capture_output=True)
    if summary.returncode: raise ValueError('summary_unavailable')
    data = json.loads(summary.stdout)
    safe = {k:data.get(k) for k in ['result','totalTestCount','passedTests','failedTests','skippedTests']}
    safe['kind'] = 'private' if private else ('accessibility' if accessibility else 'synthetic')
    if accessibility:
        audit_counts = {mode:int(count) for mode,count in re.findall(r'^T05_CONTRAST_COUNT (wallet|detail|review|source|library) (\d+)$', result.stdout.decode(errors='replace'), re.MULTILINE)}
        safe['structureAuditTypes'] = ['elementDetection', 'hitRegion', 'sufficientElementDescription']
        safe['contrastFindingsBySyntheticScenario'] = audit_counts
        safe['contrastAuditStatus'] = 'FindingsRemain' if sum(audit_counts.values()) else ('NoFindings' if len(audit_counts) == 5 else 'Incomplete')
        safe['contrastScope'] = 'Diagnostics only, never certified by the green structural/interaction test result.'
        diagnostics = [json.loads(line) for line in re.findall(r'^T05_CONTRAST_ISSUE (.+)$', result.stdout.decode(errors='replace'), re.MULTILINE)]
        safe['acceptedContrastExceptions'] = sum(d.get('acceptedException') is True for d in diagnostics)
        safe['unresolvedContrastFindings'] = sum(d.get('acceptedException') is not True for d in diagnostics)
        if diagnostics and not safe['unresolvedContrastFindings']: safe['contrastAuditStatus'] = 'FindingsWithNarrowDocumentedExceptions'
        if diagnostics: write(EVIDENCE/'contrast-diagnostics.json', {'syntheticOnly':True,'certified':False,'measurementMethod':'sRGB opaque dominant background and glyph-interior pair; antialias edges excluded. Not a complete native material-state certification.','findings':diagnostics,'run':str(run.relative_to(ROOT))})


    if private:
        container = Path(command(['xcrun','simctl','get_app_container',SIMULATOR,'com.mobyyyc.RcpLens','data']))
        reports = []
        for slot in range(5):
            path = container/'Documents/T05TestInbox'/f'slot{slot}'/'report.json'
            if path.exists():
                reports.append(json.loads(path.read_text()))
                write(run/'reports'/f'slot{slot}.json',reports[-1])
        safe['reports'] = len(reports)
        for key in ['originalBytesEqual','originalParserUnchanged','correctionMatchesReference','complete','hasGeometry']:
            safe[key] = sum(r.get(key) is True for r in reports)
        # This is aggregate only. No per-receipt arrays or arbitrary error text are public.
    write(run/'aggregate.json',safe)
    write(EVIDENCE/('private-workflow.json' if private else ('accessibility.json' if accessibility else 'synthetic-ui-tests.json')),safe)
    print(json.dumps(safe))
    return result.returncode


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('action',choices=['prepare','prepare-synthetic','private','synthetic','accessibility']); parser.add_argument('--simulator',default=SIMULATOR); args = parser.parse_args()
    globals()['SIMULATOR'] = args.simulator
    try:
        if args.action in ['prepare','prepare-synthetic']: prepare(args.action == 'prepare'); return 0
        return run(args.action == 'private',args.action == 'accessibility')
    except Exception:
        print(json.dumps({'status':'failed','reason':'local_verification_failed_no_private_details_printed'})); return 1

if __name__ == '__main__': sys.exit(main())
