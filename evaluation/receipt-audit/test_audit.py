import copy
import importlib.util
from pathlib import Path
import unittest
import tempfile

spec = importlib.util.spec_from_file_location('audit', Path(__file__).with_name('audit.py'))
a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)

def receipt(lines):
    return dict(merchant=None, date=None, subtotal=None, total=None, lines=lines)

def line(name='FICTIONAL APPLE', amount=100, kind='purchase'):
    return dict(description=name, amount=amount, kind=kind, quantity=None)

def observation(text, y=0.8):
    return dict(text=text, boundingBox=dict(x=0.1, y=y, width=0.5, height=0.02))

class AuditTests(unittest.TestCase):
    def test_amounts_include_omitted_duplicate_and_wrong_amount(self):
        expected = receipt([line(), line(), line('FICTIONAL PEAR', 200)])
        actual = receipt([line(amount=101), line(), line('FICTIONAL EXTRA', 200)])
        counts = a.amount_score(actual, expected)
        self.assertEqual(counts['items_expected'], 3)
        self.assertEqual(counts['item_amounts_correct'], 1)
        self.assertEqual(counts['omitted_lines'], 1)
        self.assertEqual(counts['invented_lines'], 1)
        self.assertEqual(counts['amount_corrections'], 1)
        self.assertEqual(counts['correction_operations'], 3)

    def test_identical_prices_do_not_establish_purchase_identity(self):
        counts = a.amount_score(receipt([line('OTHER')]), receipt([line()]))
        self.assertEqual(counts['item_amounts_correct'], 0)
        self.assertEqual(counts['omitted_lines'], 1)
        self.assertEqual(counts['invented_lines'], 1)

    def test_unknown_fields_and_quantities_do_not_fabricate_correction_effort(self):
        expected = receipt([dict(line(), quantity='1 KG')])
        actual = dict(receipt([line()]), merchant='FICTIONAL', total=100)
        original = copy.deepcopy(expected)
        self.assertEqual(a.amount_score(actual, expected)['correction_operations'], 0)
        self.assertEqual(expected, original)

    def test_tax_and_discount_are_not_purchase_recovery(self):
        expected = receipt([line(), line('FICTIONAL TAX', 13, 'tax'), line('FICTIONAL DISCOUNT', -10, 'discount')])
        counts = a.amount_score(receipt(expected['lines']), expected)
        self.assertEqual(counts['items_expected'], 1)
        self.assertEqual(counts['lines_expected'], 3)

    def test_grouping_rejects_purchase_or_image_leakage_and_exposed_holdout(self):
        dev = dict(purchase_id='fictional-1', split='development', previously_exposed=True,
                   store='Costco', images=[dict(sha256='fictional-hash')])
        held = dict(purchase_id='fictional-2', split='held_out', previously_exposed=False,
                    store='No Frills', images=[dict(sha256='other-fictional-hash')])
        self.assertEqual(a.validate_groups([dev, held]), dict(development=1, held_out=1))
        for groups in ([dev, dev], [dict(dev, split='held_out')],
                       [dev, dict(held, images=dev['images'])], [dict(dev, split='unknown')]):
            with self.assertRaises(ValueError): a.validate_groups(groups)

    def test_multiple_photos_share_one_purchase(self):
        group = dict(purchase_id='fictional', split='held_out', previously_exposed=False,
                     store='T&T', images=[dict(sha256='photo-1'), dict(sha256='photo-2')])
        self.assertEqual(a.validate_groups([group]), dict(held_out=1))

    def test_label_verification_and_digest_required(self):
        manifest = dict(receipts=[dict(id='fictional', sha256='fictional-hash')])
        label = dict(id='fictional', sha256='fictional-hash', reviewed=True,
                     verification_method='human_against_original',
                     verification_checks={k: True for k in ('fields', 'items', 'amounts', 'adjustments')},
                     expected=receipt([line()]))
        self.assertEqual(len(a.labels_for(manifest, dict(schema_version=1, receipts=[label]))), 1)
        for changed in (dict(label, sha256='wrong'), dict(label, reviewed=False),
                        dict(label, verification_checks={}), dict(label, verification_method='model_agreement')):
            with self.assertRaises(ValueError): a.labels_for(manifest, dict(schema_version=1, receipts=[changed]))
        with self.assertRaises(ValueError): a.labels_for(manifest, dict(schema_version=1, receipts=[label, label]))

    def test_taxonomy_uses_evidence_and_preserves_uncertainty(self):
        expected = receipt([line()]); actual = receipt([])
        cases = [([observation('FICTIONAL APPLE 1.00')], 'interpretation_or_description_match_suspect'),
                 ([observation('FICTIONAL APPLE'), observation('1.00', 0.7)], 'layout_association_suspect'),
                 ([observation('unreadable')], 'capture_or_ocr_or_transcription_unresolved')]
        for observations, category in cases:
            details, extras = a.diagnose(actual, expected, observations)
            self.assertEqual(details[0]['category'], category)
            self.assertEqual(extras, [])

    def test_swift_adapter_keeps_exact_signed_money_and_dates(self):
        response = dict(parsed=dict(date=dict(year=2026, month=10, day=9), total=100,
                        lines=[dict(kind='other', description='FICTIONAL', amount=-17, sourceLineIDs=['fictional'])]))
        normalized = a.normalize(response)
        self.assertEqual(normalized['date'], '2026-10-09')
        self.assertEqual(normalized['lines'][0]['amount'], -17)
        self.assertEqual(normalized['lines'][0]['kind'], 'adjustment')

    def test_archived_geometry_clamp_matches_current_recognizer(self):
        raw = dict(observations=[dict(id=1, text='FICTIONAL', x=-0.000001, y=0.99,
                   width=0.1, height=0.02, confidence=0.5)])
        converted = a.legacy_observations(raw)
        self.assertEqual(converted[0]['boundingBox']['x'], 0)
        self.assertEqual(converted[0]['boundingBox']['height'], 1-0.99)
        self.assertEqual(raw['observations'][0]['x'], -0.000001)

    def test_repetition_ignores_random_ids_but_detects_wrong_money(self):
        response = dict(parsed=dict(lines=[dict(id='one', kind='purchase', description='FICTIONAL', amount=100, sourceLineIDs=['random-one'])]))
        repeated = copy.deepcopy(response)
        repeated['parsed']['lines'][0].update(id='two', sourceLineIDs=['random-two'])
        self.assertEqual(a.stable_response(response), a.stable_response(repeated))
        repeated['parsed']['lines'][0]['amount'] = 101
        self.assertNotEqual(a.stable_response(response), a.stable_response(repeated))

    def test_private_review_is_read_only_escaped_and_has_no_network(self):
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder); (p/'current').mkdir()
            group = dict(purchase_id='fictional', images=[dict(path='/tmp/fictional.png')])
            record = dict(expected=receipt([line('</pre><script>fictional</script>')]),
                          receipt=receipt([]), failure_details=[])
            (p/'current/fictional-pass1.json').write_text('{"observations":[]}')
            a.private_review(p, [group], [record])
            page = (p/'review.html').read_text()
            self.assertNotIn('<script>', page)
            self.assertIn('&lt;script&gt;', page)
            self.assertIn("connect-src 'none'", page)
            self.assertNotIn('https://', page)
            self.assertNotIn('<input', page)

if __name__ == '__main__': unittest.main()
