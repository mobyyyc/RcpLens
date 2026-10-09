#!/usr/bin/env python3
"""P2-01 local captured protocol; print status/counts only, never receipt contents."""
import argparse
import collections
import copy
import hashlib
import html
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'evaluation/receipt-eval'))
import evaluate as e

STORES = ('Costco', 'No Frills', 'T&T')
SOURCE_FILES = ('evaluation/receipt-audit/Worker.swift', 'evaluation/receipt-audit/build.sh',
                'evaluation/receipt-audit/audit.py', 'evaluation/receipt-audit/verify.py',
                'evaluation/receipt-audit/test_audit.py', 'evaluation/receipt-eval/evaluate.py',
                'Sliplet/Domain/Receipt.swift', 'Sliplet/Domain/ReceiptReview.swift',
                'Sliplet/Domain/ReceiptSplit.swift', 'Sliplet/Domain/RecognizedText.swift',
                'Sliplet/Recognition/ReceiptImage.swift', 'Sliplet/Recognition/VisionTextRecognizer.swift',
                'Sliplet/Parsing/Parsing.swift', 'Sliplet/Persistence/ReceiptStore.swift')

def private(path):
    return e.within_private(Path(path))

def store_for(expected):
    value = e.norm(expected['merchant']).replace(' ', '')
    if 'nofrills' in value: return 'No Frills'
    if 'costco' in value: return 'Costco'
    if 't&t' in value: return 'T&T'
    raise ValueError('unclassified_store')

def validate_groups(groups):
    """All images of a purchase share one split; exposed data cannot be held out."""
    purchases, images = {}, {}
    for group in groups:
        pid, split = group['purchase_id'], group['split']
        if split not in {'development', 'held_out'}: raise ValueError('invalid_split')
        if pid in purchases: raise ValueError('duplicate_purchase')
        if group['previously_exposed'] and split == 'held_out': raise ValueError('exposed_validation')
        if group['store'] not in STORES or not group['images']: raise ValueError('invalid_group')
        purchases[pid] = split
        for image in group['images']:
            digest = image['sha256']
            if digest in images: raise ValueError('duplicate_image_purchase')
            images[digest] = pid
    return dict(collections.Counter(group['split'] for group in groups))

def labels_for(manifest, labels):
    if labels.get('schema_version') != 1: raise ValueError('invalid_labels')
    result = {}
    for label in labels['receipts']:
        if label.get('reviewed') is not True or label.get('verification_method') != 'human_against_original':
            raise ValueError('unverified_label')
        if label.get('verification_checks') != {k: True for k in ('fields', 'items', 'amounts', 'adjustments')}:
            raise ValueError('unverified_checks')
        entry = next((entry for entry in manifest['receipts'] if entry['id'] == label['id']), None)
        if entry is None or entry['sha256'] != label['sha256'] or label['id'] in result:
            raise ValueError('label_input_mismatch')
        result[label['id']] = e.validate_expected(label['expected'])
    if set(result) != {entry['id'] for entry in manifest['receipts']}: raise ValueError('incomplete_labels')
    return result

def normalize(response):
    """Adapter only: money stays Int64 cents; quantities scored separately later."""
    parsed = response.get('parsed', {})
    date = parsed.get('date')
    result = {field: parsed.get(field) for field in e.FIELDS}
    result['date'] = '%04d-%02d-%02d' % (date['year'], date['month'], date['day']) if date else None
    result['lines'] = [dict(kind='adjustment' if line['kind'] == 'other' else line['kind'],
                            description=line['description'], amount=line['amount'], quantity=None,
                            source_rows=line['sourceLineIDs']) for line in parsed.get('lines', [])]
    result['warnings'] = [issue['code'] for issue in parsed.get('issues', [])]
    return result

def amount_score(actual, expected):
    reference = copy.deepcopy(expected)
    for line in reference['lines']: line['quantity'] = None
    return e.score(actual, reference)

def match_lines(actual, expected):
    """Consume duplicates once, preferring the exact amount, as the pilot scorer does."""
    unused = list(enumerate(actual['lines']))
    pairs = []
    for index, line in enumerate(expected['lines']):
        matches = [(i, candidate) for i, candidate in unused
                   if candidate['kind'] == line['kind'] and e.norm(candidate['description']) == e.norm(line['description'])]
        found = next((x for x in matches if x[1]['amount'] == line['amount']), matches[0] if matches else None)
        if found: unused.remove(found)
        pairs.append((index, line, found))
    return pairs, unused

def money_in(text, amount):
    return any(e.cents(token.group()) == amount for token in e.MONEY.finditer(text))

def diagnose(actual, expected, observations):
    """Evidence-location suspects, not a human capture/OCR or grouping adjudication."""
    flattened = []
    for i, obs in enumerate(observations):
        box = obs.get('boundingBox')
        if box:
            flattened.append(dict(id=i, text=obs['text'], **box))
    rows = e.group_rows(flattened) if len(flattened) == len(observations) else [dict(text=x['text']) for x in observations]
    details = []
    pairs, extras = match_lines(actual, expected)
    for index, line, found in pairs:
        if found and found[1]['amount'] == line['amount']: continue
        desc = e.norm(line['description'])
        desc_rows = [r for r in rows if desc in e.norm(r['text'])]
        amount_observations = [obs for obs in observations if money_in(obs['text'], line['amount'])]
        if any(money_in(row['text'], line['amount']) for row in desc_rows):
            category = 'interpretation_or_description_match_suspect'
        elif desc_rows and amount_observations:
            category = 'layout_association_suspect'
        else:
            category = 'capture_or_ocr_or_transcription_unresolved'
        details.append(dict(reference_line_index=index, kind=line['kind'],
                            outcome='omitted' if found is None else 'wrong_amount',
                            category=category,
                            description_found_in_grouped_text=bool(desc_rows),
                            amount_found_anywhere=bool(amount_observations)))
    return details, [index for index, _ in extras]

def capture_worker(binary, request):
    start = time.monotonic()
    try:
        process = subprocess.run([str(binary)], input=json.dumps(request), text=True,
                                 capture_output=True, timeout=90)
        if process.returncode: raise ValueError('worker_exit')
        response = json.loads(process.stdout)
        if response.get('status') != 'ok': raise ValueError('worker_status')
        response['processWallMS'] = (time.monotonic() - start) * 1000
        return response
    except (OSError, ValueError, subprocess.TimeoutExpired):
        raise ValueError('private_worker_failed') from None

def legacy_observations(raw):
    result = []
    for obs in raw['observations']:
        # Mirror the current app's boundary clamp when importing archived Vision
        # geometry. The original raw values remain untouched in the archived run.
        x, y = max(0, min(1, obs['x'])), max(0, min(1, obs['y']))
        box = dict(x=x, y=y, width=min(obs['width'], 1-x), height=min(obs['height'], 1-y))
        if box['width'] <= 0 or box['height'] <= 0: box = None
        result.append(dict(id=str(uuid.uuid5(uuid.NAMESPACE_OID, str(obs['id']))), text=obs['text'],
                           engineConfidence=obs.get('confidence'), boundingBox=box))
    return result

def stable_response(response):
    receipt = normalize(response)
    for line in receipt['lines']: line.pop('source_rows', None)
    return receipt

def private_review(output, groups, records):
    """Read-only evidence page; original bytes and human labels are not edited."""
    parts = ['<!doctype html><meta charset="utf-8">',
             '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src file:; style-src \'unsafe-inline\'; connect-src \'none\'">',
             '<title>Private P2-01 evidence</title><style>body{font:16px system-ui;margin:24px}article{margin:40px 0;border-top:1px solid #aaa}img{max-width:100%;max-height:900px}pre{white-space:pre-wrap;overflow-wrap:anywhere} .cols{display:grid;grid-template-columns:1fr 1fr;gap:24px}</style>',
             '<h1>Private recognition evidence</h1><p>Read-only checked references, originals, OCR and parser output. Failure categories are automated suspects; inspect the image before adjudicating. No remote resources or uploads.</p>']
    for group, record in zip(groups, records):
        raw = json.loads((output/'current'/(group['purchase_id']+'-pass1.json')).read_text())
        parts.append('<article><h2>'+html.escape(group['purchase_id'])+'</h2><div class="cols"><div><img alt="Original receipt" src="'+html.escape(Path(group['images'][0]['path']).as_uri(), quote=True)+'"></div><div>')
        for title, value in (('Checked human reference', record['expected']),
                             ('Current parsed result', record['receipt']),
                             ('Failure evidence suspects', record['failure_details']),
                             ('Original OCR observations with geometry', raw['observations'])):
            parts.append('<h3>'+title+'</h3><pre>'+html.escape(json.dumps(value, ensure_ascii=False, indent=2))+'</pre>')
        parts.append('</div></div></article>')
    page = output/'review.html'; page.write_text('\n'.join(parts)); page.chmod(0o600)

def aggregate(records):
    output = {}
    for store in ('all',) + STORES:
        selected = [record for record in records if store == 'all' or record['store'] == store]
        counts, suspects, fields = collections.Counter(), collections.Counter(), collections.Counter()
        times = []
        stages = {name: [] for name in ('decodeMS', 'ocrMS', 'parserMS')}
        for record in selected:
            counts.update(record['score'])
            counts['reconciled'] += int(e.reconciliation(record['receipt'])['matches'])
            suspects.update(detail['category'] for detail in record['failure_details'])
            if 'expected' in record:
                pairs, extras = match_lines(record['receipt'], record['expected'])
                counts['omitted_purchases'] += sum(line['kind'] == 'purchase' and found is None for _, line, found in pairs)
                counts['extra_purchase_proxies'] += sum(line['kind'] == 'purchase' for _, line in extras)
                counts['wrong_matched_purchase_amounts'] += sum(line['kind'] == 'purchase' and found is not None and found[1]['amount'] != line['amount'] for _, line, found in pairs)
                expected, actual = record['expected'], record['receipt']
                if expected['merchant'] is not None and e.norm(actual['merchant']) != e.norm(expected['merchant']):
                    if e.norm(expected['merchant']) in e.norm(actual['merchant']):
                        fields['merchant_expected_brand_in_returned_header'] += 1
                    else: fields['merchant_capture_ocr_or_interpretation_unresolved'] += 1
            for name, values in stages.items():
                if name in record: values.append(record[name])
            if 'wall_ms' in record: times.append(record['wall_ms'])
        output[store] = dict(counts=counts, line_failure_suspects=suspects,
                             field_failure_evidence=fields,
                             mac_stage_ms_median={name: statistics.median(values) if values else None for name, values in stages.items()},
                             mac_process_wall_ms_median=statistics.median(times) if times else None,
                             mac_process_wall_ms_max=max(times) if times else None)
    return output

def run(args):
    os.umask(0o077)
    output, archived, label_path = private(args.run), private(args.archived), private(args.labels)
    if output.exists(): raise ValueError('new_run_required')
    manifest = json.loads((archived / 'manifest.json').read_text())
    checked = labels_for(manifest, json.loads(label_path.read_text()))
    # Originals only; evaluation previews/synthetic fixtures and installed stores are excluded.
    candidates = [path for path in e.PRIVATE.iterdir() if path.is_file() and path.suffix.lower() in {'.heic', '.heif', '.jpeg', '.jpg', '.png'}]
    by_hash = {e.input_digest(path): path for path in candidates}
    groups = []
    for entry in manifest['receipts']:
        path = by_hash.get(entry['sha256'])
        if path is None: raise ValueError('original_hash_unavailable')
        groups.append(dict(purchase_id=entry['id'], store=store_for(checked[entry['id']]),
                           split='development', previously_exposed=True,
                           images=[dict(path=str(path), sha256=entry['sha256'])]))
    splits = validate_groups(groups)
    sources = {name: e.input_digest(ROOT / name) for name in SOURCE_FILES}
    project = ROOT / 'Sliplet.xcodeproj/project.pbxproj'
    project_hash = e.input_digest(project)
    archived_hashes = {str(path.relative_to(archived)): e.input_digest(path)
                       for path in archived.rglob('*') if path.is_file()}
    output.mkdir(mode=0o700, parents=True)
    e.write_json(output / 'manifest.json', dict(source_sha256=sources,
                 signing_project_sha256=project_hash, archived_file_sha256=archived_hashes,
                 original_groups=groups, adapter='archived geometry clamps at unit boundaries as production does'))
    e.write_json(output / 'corpus.json', dict(schema_version=1, groups=groups,
                 target_distinct_purchases=30, target_per_store=10,
                 target_development_per_store=7, target_held_out_per_store=3,
                 additional_root_images_pending_purchase_review=len(set(by_hash) - {entry['sha256'] for entry in manifest['receipts']})))
    historical, frozen, current = [], [], []
    repeats = 0
    for entry, group in zip(manifest['receipts'], groups):
        rid, expected = entry['id'], checked[entry['id']]
        saved = json.loads((archived / 'ocr' / (rid + '.json')).read_text())
        legacy = e.parse(e.group_rows(saved['raw']['observations']))
        historical.append(dict(store=group['store'], score=dict(e.score(legacy, expected)),
                               receipt=legacy, expected=expected, failure_details=[]))
        obs = legacy_observations(saved['raw'])
        replay = capture_worker(args.worker, dict(observations=obs))
        e.write_json(output / 'frozen-swift' / (rid + '.json'), replay)
        frozen_receipt = normalize(replay)
        failures, extras = diagnose(frozen_receipt, expected, obs)
        frozen.append(dict(store=group['store'], score=dict(amount_score(frozen_receipt, expected)),
                           receipt=frozen_receipt, expected=expected, failure_details=failures))
        for pass_index in range(2):
            response = capture_worker(args.worker, dict(image=group['images'][0]['path']))
            e.write_json(output / 'current' / (rid + f'-pass{pass_index+1}.json'), response)
            if pass_index == 0:
                first = response
                actual = normalize(response)
                failures, extras = diagnose(actual, expected, response['observations'])
                details = dict(purchase_id=rid, store=group['store'], receipt=actual,
                               expected=expected, score=dict(amount_score(actual, expected)),
                               failure_details=failures, extra_actual_line_indices=extras,
                               wall_ms=response['processWallMS'],
                               **{name: response[name] for name in ('decodeMS', 'ocrMS', 'parserMS')})
                e.write_json(output / 'scores' / (rid + '.json'), details)
                current.append(details)
            else: repeats += int(stable_response(first) == stable_response(response))
    originals_preserved = all(e.input_digest(Path(group['images'][0]['path'])) == group['images'][0]['sha256'] for group in groups)
    archive_preserved = archived_hashes == {str(path.relative_to(archived)): e.input_digest(path) for path in archived.rglob('*') if path.is_file()}
    sources_preserved = sources == {name: e.input_digest(ROOT / name) for name in sources}
    project_preserved = project_hash == e.input_digest(project)
    if not all((originals_preserved, archive_preserved, sources_preserved, project_preserved)):
        raise ValueError('evidence_changed_during_audit')
    report = dict(schema_version=1, task='P2-01', measured_on='Mac; not iPhone',
                  environment=dict(macOS=platform.mac_ver()[0], machine=platform.machine(),
                                   xcode=subprocess.run(['/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild', '-version'], capture_output=True, text=True, check=True).stdout.strip()),
                  source_head=subprocess.run(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip(),
                  source_sha256=sources, worker_sha256=e.input_digest(Path(args.worker)),
                  checked_purchases=len(groups), corpus_splits=splits,
                  historical_python_reproduction=aggregate(historical),
                  production_swift_frozen_ocr=aggregate(frozen), production_swift_fresh_ocr=aggregate(current),
                  equal_successful_repeat_pairs=repeats, successful_repeat_pairs=len(groups),
                  phone_latency_ms=None, human_correction_seconds=None,
                  quantity_corrections='excluded from Swift proxy; numeric quantity adapter cannot establish printed unit/semantics',
                  failure_taxonomy='automated evidence-location suspects; capture versus OCR and actual invented lines need human adjudication',
                  preservation=dict(originals=originals_preserved, archive=archive_preserved,
                                    sources=sources_preserved, signing_project=project_preserved))
    e.write_json(output / 'aggregate.json', report)
    private_review(output, groups, current)
    print('audit_complete: checked purchases=%d, fresh OCR passes=%d; evidence private' % (len(groups), 2*len(groups)))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', required=True, type=Path)
    parser.add_argument('--archived', default=e.PRIVATE/'evaluation/real-final', type=Path)
    parser.add_argument('--labels', default=e.PRIVATE/'evaluation/real-v1/ground-truth.json', type=Path)
    parser.add_argument('--worker', default='/tmp/Sliplet-P2-01-worker', type=Path)
    try: run(parser.parse_args())
    except Exception:
        print('audit_failed; private diagnostic suppressed', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__': sys.exit(main())
