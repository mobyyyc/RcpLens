#!/usr/bin/env python3
"""Local-only T03 harness. No private data is printed; outputs stay under private-receipts."""
import argparse
import collections
import datetime as dt
import hashlib
import html
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
PRIVATE = ROOT / 'private-receipts'
VERSION = 't03-parser-0.1.1'
PROMPT_VERSION = 't03-copy-claims-0.2.0'
MONEY = re.compile(r'(?<![\d.])(-?\$?\d{1,7}\.\d{2}-?)(?!\d)')
KINDS = {'purchase', 'discount', 'tax', 'deposit', 'adjustment'}
FIELDS = ('merchant', 'date', 'subtotal', 'total')
MAX_CENTS = 10**11

def cents(value):
    if not isinstance(value, str) or not re.fullmatch(r'-?\$?\d{1,7}\.\d{2}-?', value.strip()):
        raise ValueError('invalid_money')
    value = value.strip().replace('$', '')
    negative = value.startswith('-') or value.endswith('-')
    if value.startswith('-') and value.endswith('-'): raise ValueError('invalid_money')
    whole, fraction = value.strip('-').split('.')
    result = int(whole) * 100 + int(fraction)
    if result > MAX_CENTS: raise ValueError('money_bounds')
    return -result if negative else result

def norm(text):
    return ' '.join(str(text).casefold().split())

def date_key(value):
    if value is None: return None
    for fmt in ('%Y-%m-%d', '%Y/%m/%d', '%m/%d/%Y', '%m/%d/%y', '%d-%b-%Y', '%b %d %Y'):
        try: return dt.datetime.strptime(value, fmt).date().isoformat()
        except (ValueError, TypeError): pass
    return norm(value)

def group_rows(observations):
    """Top to bottom, left to right; preserve original observations separately."""
    groups = []
    for obs in sorted(observations, key=lambda o: (-(o['y'] + o['height']/2), o['x'])):
        center = obs['y'] + obs['height']/2
        match = next((g for g in groups if abs(g['center'] - center) <= min(g['height'], obs['height']) * 0.45), None)
        if match is None:
            groups.append({'center': center, 'height': obs['height'], 'parts': [obs]})
        else: match['parts'].append(obs)
    return [{'id': i, 'text': ' '.join(p['text'] for p in sorted(g['parts'], key=lambda p: p['x'])),
             'observation_ids': [p['id'] for p in sorted(g['parts'], key=lambda p: p['x'])]}
            for i, g in enumerate(sorted(groups, key=lambda g: -g['center']))]

def empty_receipt():
    return {**{f: None for f in FIELDS}, 'lines': [], 'evidence': {}, 'warnings': []}

def parse(rows):
    result = empty_receipt()
    in_items = False
    finished = False
    pending = None
    for row in rows:
        text = row['text'].strip()
        upper = text.upper()
        if result['merchant'] is None:
            merchant = re.search(r'(NO\s*FRILLS|COSTCO|T\s*&\s*T)', upper)
            if merchant:
                result['merchant'] = text
                result['evidence']['merchant'] = [row['id']]
        if result['date'] is None:
            date = re.search(r'\b(?:20\d{2}[-/]\d{2}[-/]\d{2}|\d{1,2}/\d{1,2}/(?:20)?\d{2}|\d{1,2}-[A-Za-z]{3}-20\d{2})\b', text)
            if date:
                result['date'] = date.group()
                result['evidence']['date'] = [row['id']]
        amounts = list(MONEY.finditer(text))
        if not amounts:
            if in_items and not finished and re.search(r'\b(?:\d+(?:\.\d+)?\s*(?:KG|LB|X|@)|QTY)\b', upper):
                pending = row
            continue
        last = amounts[-1]
        amount = cents(last.group())
        prefix = text[:last.start()].strip()
        if re.match(r'^(?:SUB\s*TOTAL|SOUS[- ]?TOTAL)\b', upper):
            result['subtotal'] = amount; result['evidence']['subtotal'] = [row['id']]; finished = True; continue
        if re.match(r'^(?:GRAND\s+)?TOTAL\b', upper) and not re.match(r'^TOTAL\s+(?:SAVINGS|ITEMS|DISCOUNT)', upper):
            result['total'] = amount; result['evidence']['total'] = [row['id']]; finished = True; continue
        tax = re.match(r'^(?:HST|GST|PST|QST|TPS|TVQ|TAX|TAXES)\b', upper)
        adjustment = re.match(r'^(?:DISCOUNT|COUPON|SAVINGS|DEPOSIT|ADJUSTMENT)\b', upper)
        kind = 'tax' if tax else ('discount' if amount < 0 else 'purchase')
        if adjustment:
            kind = 'deposit' if upper.startswith('DEPOSIT') else ('discount' if amount < 0 else 'adjustment')
        if finished and not (tax or adjustment): continue
        if re.match(r'^(?:CASH|VISA|MASTERCARD|DEBIT|CREDIT|CHANGE|TENDER|BALANCE|SAVINGS|YOU SAVED|MEMBER|REGISTER|AUTH|TRANSACTION)\b', upper): continue
        if not prefix or not re.search(r'[^\W\d_]', prefix, re.UNICODE): continue
        # Skip a standalone unit-price/weight expression; retain as quantity evidence.
        if re.match(r'^\d+(?:\.\d+)?\s*(?:KG|LB|X|@)\b', upper): pending = row; continue
        ids = [row['id']]
        quantity = None
        q = re.search(r'\b\d+(?:\.\d+)?\s*(?:KG|LB|X|@)\s*.*', prefix, re.I)
        if q: quantity = q.group()
        elif pending: quantity = pending['text']; ids.insert(0, pending['id'])
        result['lines'].append({'kind': kind, 'description': prefix, 'amount': amount, 'quantity': quantity, 'source_rows': ids})
        pending = None; in_items = True
    if result['merchant'] is None: result['warnings'].append('merchant_missing')
    if result['date'] is None: result['warnings'].append('date_missing')
    if result['total'] is None: result['warnings'].append('total_missing')
    return result

def validate_proposal(proposal, rows):
    """Reject missing provenance or mutated numeric values. No repairs or arithmetic inference."""
    result = empty_receipt()
    if not isinstance(proposal, dict) or set(proposal) != set(FIELDS) | {'lines'}:
        result['warnings'].append('malformed_schema'); return result
    def claim(c, money=False):
        if not isinstance(c, dict) or set(c) != {'value', 'quote'} or not all(isinstance(c[k], str) for k in c):
            raise ValueError('malformed_claim')
        if not c['value'] and not c['quote']: return None, []
        if not c['value'] or not c['quote'] or norm(c['value']) not in norm(c['quote']): raise ValueError('ungrounded_value')
        hits = [r['id'] for r in rows if norm(c['quote']) in norm(r['text'])]
        if not hits: raise ValueError('ungrounded_quote')
        # Literal decimal must be a bounded token within quote (1.00 cannot ground on 11.00).
        if money and c['value'] not in [m.group() for m in MONEY.finditer(c['quote'])]: raise ValueError('ungrounded_amount')
        return (cents(c['value']) if money else c['value']), hits
    for field in FIELDS:
        try:
            result[field], ids = claim(proposal[field], field in ('subtotal', 'total'))
            if ids: result['evidence'][field] = ids
        except ValueError as e: result['warnings'].append(field + '_' + str(e))
    if not isinstance(proposal['lines'], list) or len(proposal['lines']) > 500:
        result['warnings'].append('malformed_lines'); return result
    for line in proposal['lines']:
        try:
            if not isinstance(line, dict) or set(line) != {'kind', 'description', 'amount', 'quantity'} or line['kind'] not in KINDS:
                raise ValueError('malformed_line')
            desc, di = claim(line['description']); amount, ai = claim(line['amount'], True); quantity, qi = claim(line['quantity'])
            if desc is None or amount is None: raise ValueError('missing_line_value')
            if not set(di).intersection(ai): raise ValueError('description_amount_different_rows')
            matching = [r for r in rows if r['id'] in set(di).intersection(ai)]
            if not any(list(MONEY.finditer(r['text'])) and cents(list(MONEY.finditer(r['text']))[-1].group()) == amount for r in matching): raise ValueError('not_printed_line_extension')
            if line['kind'] == 'discount' and amount > 0: raise ValueError('unsigned_discount')
            result['lines'].append({'kind': line['kind'], 'description': desc, 'amount': amount,
                                    'quantity': quantity, 'source_rows': sorted(set(di + ai + qi))})
        except (ValueError, TypeError) as e:
            reason = str(e) if isinstance(e, ValueError) else 'malformed_line'
            result['warnings'].append('line_' + reason)
    # Every duplicate is exposed; repeated printed purchases are allowed but cannot reuse evidence.
    seen = set()
    for line in result['lines']:
        key = (line['kind'], tuple(line['source_rows']), line['amount'])
        if key in seen: result['warnings'].append('duplicate_source_line')
        seen.add(key)
    return result

def reconciliation(receipt):
    total = receipt['total']
    if total is None or not receipt['lines']: return {'eligible': False, 'matches': False}
    total_lines = sum(line['amount'] for line in receipt['lines'])
    subtotal_matches = None
    if receipt['subtotal'] is not None:
        subtotal_matches = sum(l['amount'] for l in receipt['lines'] if l['kind'] != 'tax') == receipt['subtotal']
    return {'eligible': True, 'matches': total_lines == total, 'subtotal_matches': subtotal_matches,
            'difference_cents': total_lines - total} # Private result only; public output uses boolean counts.

def score(actual, expected):
    counts = collections.Counter()
    for field in FIELDS:
        a, e = actual[field], expected[field]
        if e is not None:
            counts[field + '_expected'] += 1
            counts[field + '_correct'] += int(date_key(a) == date_key(e) if field == 'date' else (norm(a) == norm(e) if field == 'merchant' else a == e))
        # Null reference values are unscored unknown/unreadable, not confirmed absence.
        if e is not None:
            counts['field_corrections'] += int((date_key(a) != date_key(e)) if field == 'date' else (norm(a) != norm(e) if field == 'merchant' else a != e))
    unused = list(actual['lines'])
    for line in expected['lines']:
        counts['lines_expected'] += 1
        if line['kind'] == 'purchase': counts['items_expected'] += 1
        matches = [i for i, item in enumerate(unused) if item['kind'] == line['kind'] and norm(item['description']) == norm(line['description'])]
        if not matches:
            counts['omitted_lines'] += 1; continue
        idx = next((i for i in matches if unused[i]['amount'] == line['amount']), matches[0])
        found = unused.pop(idx)
        counts['detected_lines'] += 1
        correct = found['amount'] == line['amount']
        counts['line_amounts_correct'] += int(correct)
        if line['kind'] == 'purchase': counts['item_amounts_correct'] += int(correct)
        counts['amount_corrections'] += int(not correct)
        if line.get('quantity') is not None:
            counts['quantity_corrections'] += int(norm(found.get('quantity')) != norm(line['quantity']))
    counts['invented_lines'] = len(unused)
    counts['correction_operations'] = sum(counts[k] for k in ('field_corrections', 'amount_corrections', 'quantity_corrections', 'omitted_lines', 'invented_lines'))
    counts['receipts_scored'] = 1
    return counts

def validate_expected(expected):
    if not isinstance(expected, dict) or set(expected) != set(FIELDS) | {'lines'}: raise ValueError('invalid_labels')
    for field in ('merchant', 'date'):
        if expected[field] is not None and (not isinstance(expected[field], str) or not expected[field].strip()): raise ValueError('invalid_labels')
    for field in ('subtotal', 'total'):
        if expected[field] is not None and (type(expected[field]) is not int or abs(expected[field]) > MAX_CENTS): raise ValueError('invalid_labels')
    if not isinstance(expected['lines'], list) or len(expected['lines']) > 500: raise ValueError('invalid_labels')
    for line in expected['lines']:
        if not isinstance(line, dict) or set(line) != {'kind', 'description', 'amount', 'quantity'}: raise ValueError('invalid_labels')
        if line['kind'] not in KINDS or not isinstance(line['description'], str) or not line['description'].strip(): raise ValueError('invalid_labels')
        if type(line['amount']) is not int or abs(line['amount']) > MAX_CENTS: raise ValueError('invalid_labels')
        if line['quantity'] is not None and not isinstance(line['quantity'], str): raise ValueError('invalid_labels')
    return expected

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    path.chmod(0o600)

def worker(binary, request, timeout=90):
    started = time.monotonic()
    try:
        result = subprocess.run([str(binary)], input=json.dumps(request), text=True, capture_output=True, timeout=timeout)
        # stderr is intentionally discarded: Apple framework diagnostics may contain private context.
        if result.returncode != 0: return {'status': 'worker_failed', 'latency_ms': int((time.monotonic()-started)*1000)}
        decoded = json.loads(result.stdout)
        if not isinstance(decoded, dict) or not isinstance(decoded.get('status'), str): raise ValueError()
        decoded['wall_latency_ms'] = int((time.monotonic()-started)*1000)
        return decoded
    except subprocess.TimeoutExpired: return {'status': 'worker_timeout', 'latency_ms': int((time.monotonic()-started)*1000)}
    except (ValueError, OSError): return {'status': 'worker_protocol_error', 'latency_ms': int((time.monotonic()-started)*1000)}

def input_digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def within_private(path):
    path = path.resolve()
    if not path.is_relative_to(PRIVATE.resolve()): raise ValueError('private_output_required')
    return path

def summary(run, labels=None):
    manifest = json.loads((run/'manifest.json').read_text())
    expected = {}
    review_seconds = []
    if labels:
        label_doc = json.loads(within_private(labels).read_text())
        if label_doc.get('schema_version') != 1: raise ValueError('invalid_labels')
        for label in label_doc['receipts']:
            if label.get('reviewed') is not True or label.get('verification_method') != 'human_against_original': continue
            if manifest['corpus_kind'] == 'private_real' and label.get('verification_checks') != {'fields': True, 'items': True, 'amounts': True, 'adjustments': True}: continue
            entry = next((e for e in manifest['receipts'] if e['id'] == label['id'] and e['sha256'] == label['sha256']), None)
            if not entry: raise ValueError('label_input_mismatch')
            if label['id'] in expected: raise ValueError('duplicate_label')
            expected[label['id']] = validate_expected(label['expected'])
            seconds = label.get('correction_seconds')
            if type(seconds) in (int, float) and seconds >= 0: review_seconds.append(seconds)
    output = {'schema_version': 1, 'parser_version': VERSION, 'prompt_version': PROMPT_VERSION,
              'corpus_kind': manifest['corpus_kind'], 'configuration':manifest.get('configuration',{}), 'receipt_count': len(manifest['receipts']),
              'human_verified_receipts': len(expected) if manifest['corpus_kind'] == 'private_real' else 0,
              'golden_synthetic_receipts': len(expected) if manifest['corpus_kind'] == 'synthetic' else 0,
              'accuracy_status': 'measured_against_labels' if expected else 'pending_independent_ground_truth',
              'environment': manifest['environment'], 'approaches': {}, 'retailer_coverage_basis': 'provisional_ocr',
              'retailer_counts': dict(collections.Counter(e['retailer'] for e in manifest['receipts'])),
              'human_correction_seconds_count': len(review_seconds),
              'human_correction_seconds_median': statistics.median(review_seconds) if review_seconds else None}
    for approach in ('A', 'B', 'C'):
        records = []
        for entry in manifest['receipts']:
            path = run/'results'/f"{entry['id']}-{approach}.json"
            if path.exists(): records.append((entry['id'], json.loads(path.read_text())))
        counts = collections.Counter(); latencies = []; statuses = collections.Counter(); repeat = []
        for rid, record in records:
            statuses[record['status']] += 1
            latencies.append(record['end_to_end_ms'])
            if record['status'] == 'ok':
                counts['generated_receipts'] += 1
                checks = reconciliation(record['receipt'])
                counts['reconciliation_eligible'] += int(checks['eligible'])
                counts['reconciled'] += int(checks['matches'])
                counts['validation_warnings'] += len(record['receipt']['warnings'])
                counts['proposed_lines'] += record.get('proposed_line_count',len(record['receipt']['lines']))
                counts['accepted_lines'] += len(record['receipt']['lines'])
                counts['rejected_lines'] += max(0,record.get('proposed_line_count',len(record['receipt']['lines'])) - len(record['receipt']['lines']))
            if rid in expected:
                counts.update(score(record.get('receipt', empty_receipt()), expected[rid]))
            repeat_path = run/'results'/f'{rid}-{approach}-repeat.json'
            if repeat_path.exists():
                repeated = json.loads(repeat_path.read_text())
                repeat.append({'both_success':record['status']=='ok' and repeated['status']=='ok', 'status_equal':record['status']==repeated['status'], 'output_equal':record.get('receipt')==repeated.get('receipt'), 'same_failure':record['status']!='ok' and repeated['status']==record['status']})
        metrics = dict(counts)
        for field in FIELDS:
            den = counts[field+'_expected']; metrics[field+'_accuracy'] = counts[field+'_correct']/den if den else None
        for metric, n, d in [('item_amount_accuracy','item_amounts_correct','items_expected'), ('line_amount_accuracy','line_amounts_correct','lines_expected'), ('line_recall','detected_lines','lines_expected')]:
            metrics[metric] = counts[n]/counts[d] if counts[d] else None
        metrics['reconciliation_rate_all_inputs'] = counts['reconciled']/len(manifest['receipts']) if records else None
        output['approaches'][approach] = {'attempted': len(records), 'statuses': dict(statuses), 'metrics': metrics,
                'latency_ms_median': statistics.median(latencies) if latencies else None,
                'latency_ms_max': max(latencies) if latencies else None,
                'repeat_pairs':len(repeat), 'repeat_success_pairs':sum(r['both_success'] for r in repeat), 'repeat_success_output_equal':sum(r['both_success'] and r['output_equal'] for r in repeat), 'repeat_status_equal':sum(r['status_equal'] for r in repeat), 'repeat_same_failure':sum(r['same_failure'] for r in repeat), 'repeat_failed_pairs':sum(not r['both_success'] for r in repeat)}
    write_json(run/'aggregate.json', output)
    return output

def make_review(run, manifest):
    payload=[]
    for entry in manifest['receipts']:
        result=json.loads((run/'results'/f"{entry['id']}-A.json").read_text())
        candidate=result['receipt']
        draft={**{f:candidate[f] for f in FIELDS}, 'lines':[{k:line[k] for k in ('kind','description','amount','quantity')} for line in candidate['lines']]}
        payload.append({'id':entry['id'],'sha256':entry['sha256'],'original':Path(entry['image']).as_uri(),'draft':draft})
    template = r'''<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self' file:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'"><title>Private receipt verification</title>
<style>body{font:17px system-ui;margin:28px;background:#f4f4f4;color:#111}article{border-top:1px solid #ccc;margin:32px 0;padding-top:16px}.layout{display:grid;grid-template-columns: minmax(320px,1fr) minmax(600px,1.5fr);gap:24px}.source{max-height:85vh;overflow:auto;position:sticky;top:16px}.source img{width:100%;cursor:zoom-in}input,select,button{font:inherit;padding:8px;border:1px solid #aaa;border-radius:6px}button{cursor:pointer;background:white;margin:5px}input[type=checkbox]{width:22px;height:22px}label{display:block;margin:12px 0}.fields{display:grid;grid-template-columns:1fr 1fr;gap:12px}.fields input{width:90%}table{width:100%;border-collapse:collapse;font-size:14px}td{padding:5px}td input{width:90%;min-width:60px}td:nth-child(2){width:35%}.checks{background:#fff;padding:16px;margin-top:16px}.badge{color:#8a4500;font-weight:600}.error{color:#a00}@media(max-width:950px){.layout{display:block}.source{position:static;max-height:500px}}</style>
<h1>Private receipt verification</h1><p>Everything stays in this local page. First load an <b>unverified Vision draft</b> for speed, or start blank. Check and correct it against the original image: pipeline agreement is not verification. Click the image to enlarge it. Your checks become the human reference labels only after all four confirmations.</p><p>Copy printed line extensions, including negative discounts, taxes and deposits. Do not calculate missing amounts. Leave unknown fields blank. Preserve printed item names and quantities. A matching total alone does not prove complete item coverage.</p><div id="cards"></div><button onclick="save()">Export human-verified labels</button><p id="message"></p>
<script>
const data=PAYLOAD, kinds=['purchase','discount','tax','deposit','adjustment'];
const money=c=>c==null?'':(c<0?'-':'')+Math.floor(Math.abs(c)/100)+'.'+String(Math.abs(c)%100).padStart(2,'0');
function cents(s){if(!s.trim())return null;if(!/^-?\d{1,7}\.\d{2}$/.test(s.trim()))throw Error('Amounts need two decimal places.');let t=s.trim(),negative=t[0]==='-';t=t.replace('-','');const [a,b]=t.split('.');return Number((negative?-1n:1n)*(BigInt(a)*100n+BigInt(b)));}
function reset(a){a.querySelectorAll('.checks input').forEach(c=>c.checked=false);a.querySelector('.badge').textContent='Unverified — check original after every change';}
function row(a,v={kind:'purchase',description:'',amount:null,quantity:null}){const tr=document.createElement('tr');const sel=document.createElement('select');sel.setAttribute('aria-label','Line type');kinds.forEach(k=>{const o=document.createElement('option');o.textContent=k;o.value=k;sel.append(o)});sel.value=v.kind;const controls=[sel];for(const [key,label] of [['description','Printed description'],['amount','Printed line amount'],['quantity','Printed quantity or weight']]){const i=document.createElement('input');i.setAttribute('aria-label',label);i.value=key==='amount'?money(v[key]):v[key]||'';controls.push(i)}controls.forEach(c=>{const td=document.createElement('td');td.append(c);tr.append(td);c.onchange=()=>reset(a);c.oninput=()=>reset(a)});const td=document.createElement('td'),btn=document.createElement('button');btn.textContent='Remove';btn.onclick=()=>{tr.remove();reset(a)};td.append(btn);tr.append(td);a.querySelector('tbody').append(tr);reset(a);}
function fill(a,v){a.querySelectorAll('.field').forEach(i=>i.value=['subtotal','total'].includes(i.dataset.field)?money(v[i.dataset.field]):v[i.dataset.field]||'');a.querySelector('tbody').replaceChildren();v.lines.forEach(v=>row(a,v));reset(a);}
for(const d of data){const a=document.createElement('article');a.dataset.id=d.id;a.innerHTML='<h2></h2><div class="layout"><div class="source"><a target="_blank"><img alt="Private original receipt"></a></div><div><p class="badge">Blank, unverified</p><button class="draft">Load unverified Vision draft</button><button class="blank">Start blank</button><div class="fields"></div><h3>All printed lines</h3><table><thead><tr><th>Type</th><th>Description</th><th>Amount</th><th>Quantity</th><th></th></tr></thead><tbody></tbody></table><button class="add">Add line</button><div class="checks"></div></div></div>';a.querySelector('h2').textContent=d.id;a.querySelector('img').src='previews/'+d.id+'.jpg';a.querySelector('a').href='previews/'+d.id+'.jpg';const original=document.createElement('a');original.href=d.original;original.target='_blank';original.textContent='Open original HEIC/image';a.querySelector('.source').prepend(original);['merchant','date','subtotal','total'].forEach(f=>{const l=document.createElement('label');l.textContent=f;const i=document.createElement('input');i.className='field';i.dataset.field=f;i.oninput=()=>reset(a);l.append(i);a.querySelector('.fields').append(l)});for(const [key,text] of [['fields','Merchant, date, subtotal and total match the image; blank means unreadable or absent.'],['items','All purchase lines are included once; names and quantities match.'],['amounts','Every amount is the printed line extension, not a unit price or computed value.'],['adjustments','All discounts, taxes, deposits and adjustments are included with the correct sign.']]){const l=document.createElement('label'),c=document.createElement('input');c.type='checkbox';c.dataset.check=key;l.append(c,document.createTextNode(' '+text));a.querySelector('.checks').append(l)}a.querySelector('.draft').onclick=()=>fill(a,d.draft);a.querySelector('.blank').onclick=()=>fill(a,{merchant:null,date:null,subtotal:null,total:null,lines:[]});a.querySelector('.add').onclick=()=>row(a);document.getElementById('cards').append(a);}
function save(){try{const receipts=[...document.querySelectorAll('article')].map(a=>{const d=data.find(d=>d.id===a.dataset.id);const checks=Object.fromEntries([...a.querySelectorAll('.checks input')].map(c=>[c.dataset.check,c.checked]));if(Object.values(checks).some(c=>!c))throw Error('Verify all four checks for each receipt.');const expected={};a.querySelectorAll('.field').forEach(i=>expected[i.dataset.field]=['total','subtotal'].includes(i.dataset.field)?cents(i.value):i.value.trim()||null);expected.lines=[...a.querySelectorAll('tbody tr')].map(tr=>{const c=tr.querySelectorAll('select,input');if(!c[1].value.trim()||cents(c[2].value)==null)throw Error('Every line needs a description and printed amount.');return {kind:c[0].value,description:c[1].value.trim(),amount:cents(c[2].value),quantity:c[3].value.trim()||null}});return {id:d.id,sha256:d.sha256,reviewed:true,verification_method:'human_against_original',verification_checks:checks,correction_seconds:null,expected}});const blob=new Blob([JSON.stringify({schema_version:1,receipts},null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download='ground-truth.json';link.click();URL.revokeObjectURL(url);document.getElementById('message').textContent='Save ground-truth.json beside this page, then tell the main chat labels are ready.'}catch(e){document.getElementById('message').textContent=e.message;}}
</script>'''
    safe=json.dumps(payload,ensure_ascii=False).replace('<',r'\u003c').replace('>',r'\u003e').replace('&',r'\u0026')
    (run/'review.html').write_text(template.replace('PAYLOAD',safe))
    (run/'review.html').chmod(0o600)

def prepare(args):
    run = within_private(args.run)
    if (run/'manifest.json').exists(): raise ValueError('run_already_exists')
    run.mkdir(parents=True, mode=0o700)
    env = worker(args.worker, {'operation':'probe'})
    if env['status'] != 'ok': raise ValueError('probe_failed')
    manifest = {'schema_version':1, 'corpus_kind': 'synthetic' if args.synthetic else 'private_real', 'environment': env, 'receipts': []}
    if args.synthetic:
        cases = json.loads((Path(__file__).parent/'fixtures/golden.json').read_text())
        source = run/'synthetic-images'; source.mkdir(mode=0o700)
        paths = []
        for i, case in enumerate(cases):
            path = source/f'synthetic-{i+1:03}.png'
            result = worker(args.worker, {'operation':'render','text':case['text'],'output':str(path)})
            if result['status'] != 'ok': raise ValueError('render_failed')
            paths.append(path)
    else:
        corpus = within_private(args.corpus)
        paths = sorted(p for p in corpus.iterdir() if p.is_file() and p.suffix.lower() in ('.heic','.jpeg','.jpg','.png'))
    if not paths: raise ValueError('empty_corpus')
    for i, path in enumerate(paths):
        rid = f'r{i+1:03}'
        ocr = worker(args.worker, {'operation':'ocr','image':str(path)})
        rows = group_rows(ocr.get('observations', []))
        write_json(run/'ocr'/f'{rid}.json', {'raw':ocr,'rows':rows})
        receipt = parse(rows)
        retailer = 'unknown'
        merchant = (receipt['merchant'] or '').upper()
        if 'FRILLS' in merchant: retailer = 'No Frills'
        elif 'COSTCO' in merchant: retailer = 'Costco'
        elif re.search(r'T\s*&\s*T', merchant): retailer = 'T&T'
        entry = {'id':rid,'image':str(path.resolve()),'sha256':input_digest(path),'retailer':retailer}
        manifest['receipts'].append(entry)
        write_json(run/'results'/f'{rid}-A.json', {'status':ocr['status'], 'receipt':receipt,'end_to_end_ms':ocr['wall_latency_ms'],'ocr_ms':ocr['latency_ms'],'parser_version':VERSION})
        repeat = worker(args.worker, {'operation':'ocr','image':str(path)})
        write_json(run/'ocr'/f'{rid}-repeat.json', repeat)
        write_json(run/'results'/f'{rid}-A-repeat.json', {'status':repeat['status'],'receipt':parse(group_rows(repeat.get('observations',[]))), 'end_to_end_ms':repeat['wall_latency_ms']})
        preview = run/'previews'/f'{rid}.jpg'; preview.parent.mkdir(exist_ok=True,mode=0o700)
        if worker(args.worker, {'operation':'preview','image':str(path),'output':str(preview)})['status'] != 'ok': raise ValueError('preview_failed')
        preview.chmod(0o600)
        print(f'prepared {i+1}/{len(paths)}', flush=True)
    write_json(run/'manifest.json', manifest)
    make_review(run, manifest)
    if args.synthetic:
        write_json(run/'ground-truth.json', {'schema_version':1, 'receipts':[{'id':e['id'],'sha256':e['sha256'],'reviewed':True,'verification_method':'human_against_original','expected':case['expected']} for e,case in zip(manifest['receipts'], cases)]})
    summary(run, run/'ground-truth.json' if args.synthetic else None)
    print('prepare complete; private review created', flush=True)

def benchmark(args):
    run = within_private(args.run)
    manifest = json.loads((run/'manifest.json').read_text())
    for i, entry in enumerate(manifest['receipts']):
        image = within_private(Path(entry['image']))
        if input_digest(image) != entry['sha256']: raise ValueError('input_changed')
        ocr = json.loads((run/'ocr'/f"{entry['id']}.json").read_text())
        rows = ocr['rows']
        for approach in args.approaches:
            for repeat in range(args.repeats):
                dest = run/'results'/f"{entry['id']}-{approach}{'-repeat' if repeat else ''}.json"
                if dest.exists(): continue
                if ocr['raw']['status'] != 'ok' and approach == 'B':
                    output = {'status':'ocr_failed','latency_ms':0}
                else:
                    request = {'operation':'text','text':'\n'.join(r['text'] for r in rows)} if approach == 'B' else {'operation':'image','image':str(image)}
                    output = worker(args.worker, request)
                write_json(run/'raw-model'/dest.name, output)
                receipt = validate_proposal(output.get('receipt'), rows) if output['status']=='ok' else empty_receipt()
                # C has independent image/tool input. Its claims are conservatively gated against A's OCR;
                # this may reject correct C-only text, and must be considered in interpretation.
                result = {'status': output['status'], 'receipt': receipt,
                          'end_to_end_ms':output.get('wall_latency_ms',output['latency_ms']) + (ocr['raw']['wall_latency_ms'] if approach=='B' else 0),
                          'model_ms':output['latency_ms'],'prompt_version':PROMPT_VERSION,
                          'grounding_basis':'shared_Vision_rows', 'input_tokens':output.get('input_tokens'), 'output_tokens':output.get('output_tokens'), 'failure_phase':output.get('failure_phase'), 'error_category':output.get('error_category'), 'error_code':output.get('error_code'), 'proposed_line_count':len(output.get('receipt',{}).get('lines',[]))}
                write_json(dest,result)
                print(f'benchmarked {i+1}/{len(manifest["receipts"])} {approach} pass {repeat+1}: {output["status"]}',flush=True)
                summary(run, args.labels)
    print('benchmark complete',flush=True)

def main():
    os.umask(0o077)
    ap=argparse.ArgumentParser()
    ap.add_argument('--worker',type=Path,default=Path('/tmp/RcpLens-T03-worker'))
    commands=ap.add_subparsers(dest='command',required=True)
    prep=commands.add_parser('prepare'); prep.add_argument('--run',type=Path,required=True); prep.add_argument('--corpus',type=Path,default=PRIVATE); prep.add_argument('--synthetic',action='store_true')
    bench=commands.add_parser('benchmark'); bench.add_argument('--run',type=Path,required=True); bench.add_argument('--approaches',nargs='+',choices=['B','C'],default=['B','C']); bench.add_argument('--repeats',type=int,choices=[1,2],default=2); bench.add_argument('--labels',type=Path)
    report=commands.add_parser('report'); report.add_argument('--run',type=Path,required=True); report.add_argument('--labels',type=Path)
    args=ap.parse_args()
    try:
        if args.command=='prepare': prepare(args)
        elif args.command=='benchmark': benchmark(args)
        else:
            result=summary(within_private(args.run),args.labels)
            print(json.dumps(result,indent=2)) # Only the explicit aggregate schema is printable.
    except Exception:
        print('evaluation_failed; inspect code/configuration locally; private error suppressed',file=sys.stderr)
        return 1
    return 0
if __name__=='__main__': sys.exit(main())
