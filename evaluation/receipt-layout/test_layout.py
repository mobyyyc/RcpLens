import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

import compare as c

def line(text, x=0.1, y=0.7, width=0.4, height=0.02, box=True):
    result = dict(id=str(uuid.uuid4()).upper(), text=text, engineConfidence=0.9)
    if box: result['boundingBox'] = dict(x=x, y=y, width=width, height=height)
    return result

class LayoutTests(unittest.TestCase):
    def replay(self, observations, mode='text-association', **extra):
        response = c.a.capture_worker(Path('/tmp/Sliplet-P2-02-worker'), dict(observations=observations, mode=mode, **extra))
        c.verify_membership(response)
        self.assertEqual(response['observations'], observations)
        return response

    def test_detached_price_joins_mixed_language_and_sku(self):
        obs = [line('COSTCO CAD', y=.95), line('123456 茶 TEA'), line('2.50', x=.8, y=.684, width=.1)]
        response = self.replay(obs)
        self.assertEqual(response['parsed']['lines'][0]['description'], '123456 茶 TEA')
        self.assertEqual(response['parsed']['lines'][0]['amount'], 250)
        self.assertEqual(set(response['parsed']['lines'][0]['sourceLineIDs']), {obs[1]['id'], obs[2]['id']})

    def test_ambiguous_descriptions_leave_detached_price(self):
        obs = [line('FIRST', y=.70), line('SECOND', y=.68), line('2.50', x=.8, y=.69, width=.1)]
        response = self.replay(obs)
        groups = response['groupedRowIDs']
        self.assertIn([obs[2]['id']], groups)

    def test_same_column_and_far_price_never_attach(self):
        obs = [line('ITEM'), line('2.50', x=.1, y=.684, width=.1), line('3.50', x=.8, y=.5, width=.1)]
        self.assertEqual(len(self.replay(obs)['groupedRowIDs']), 3)

    def test_two_competing_prices_do_not_attach(self):
        obs = [line('ITEM'), line('2.50', x=.7, y=.684, width=.1), line('3.50', x=.9, y=.686, width=.09)]
        response = self.replay(obs)
        self.assertIn([obs[0]['id']], response['groupedRowIDs'])

    def test_missing_geometry_preserves_input_order(self):
        obs = [line('BOTTOM', y=.1), line('UNKNOWN', box=False), line('TOP', y=.9)]
        response = self.replay(obs)
        self.assertEqual(response['groupedRowIDs'], [[o['id']] for o in obs])

    def test_long_receipt_retains_first_last_and_all_ids(self):
        obs = [line(f'{100000+i} ITEM 茶', y=.99-i*.002, height=.001) for i in range(480)]
        response = self.replay(obs, 'text-column-association')
        self.assertEqual(len(response['observations']), 480)
        self.assertEqual(response['groupedRowIDs'][0], [obs[0]['id']])
        self.assertEqual(response['groupedRowIDs'][-1], [obs[-1]['id']])

    def test_document_rows_preserve_source_ids_and_remaining_footer(self):
        obs = [line('COSTCO CAD', y=.95), line('TEA', y=.7), line('2.50', x=.8, y=.68, width=.1), line('TOTAL 2.50', y=.1)]
        ids = [[obs[1]['id'], obs[2]['id']]]
        response = self.replay(obs, 'document-tables', tableRowIDs=ids)
        self.assertEqual(response['parsed']['total'], 250)
        self.assertEqual(response['parsed']['lines'][0]['sourceLineIDs'], ids[0])
        self.assertEqual(response['tableRowsApplied'], 1)

    def test_spanning_cell_across_rows_falls_back(self):
        obs = [line('ITEM'), line('2.50', x=.8, width=.1)]
        response = self.replay(obs, 'document-tables', tableRowIDs=[[obs[0]['id']], [obs[0]['id'], obs[1]['id']]])
        baseline = self.replay(obs, 'baseline')
        self.assertEqual(response['groupedRowIDs'], baseline['groupedRowIDs'])
        self.assertEqual(response['tableFallbackReason'], 'spanning_or_duplicate_cell_line_uuid')
        self.assertEqual(response['tableRowsApplied'], 0)

    def test_unknown_cell_uuid_falls_back(self):
        obs = [line('ITEM'), line('2.50', x=.8, width=.1)]
        response = self.replay(obs, 'document-tables', tableRowIDs=[[str(uuid.uuid4())]])
        self.assertEqual(len(response['groupedRowIDs']), 1)
        self.assertEqual(response['tableFallbackReason'], 'unknown_cell_line_uuid')

    def test_duplicate_or_lost_observation_rejected(self):
        obs = [line('ITEM')]
        good = self.replay(obs)
        for ids in ([], [[obs[0]['id'], obs[0]['id']]]):
            bad = copy.deepcopy(good); bad['groupedRowIDs'] = ids
            with self.assertRaises(ValueError): c.verify_membership(bad)

    def test_unknown_provenance_and_invalid_coordinate_rejected(self):
        good = self.replay([line('ITEM 2.50')])
        bad = copy.deepcopy(good); bad['parsed']['lines'][0]['sourceLineIDs'] = [str(uuid.uuid4())]
        with self.assertRaises(ValueError): c.verify_membership(bad)
        bad = copy.deepcopy(good); bad['observations'][0]['boundingBox']['x'] = 2
        with self.assertRaises(ValueError): c.verify_membership(bad)

    def test_failed_worker_does_not_expose_input(self):
        result = subprocess.run(['/tmp/Sliplet-P2-02-worker'], input='{"mode":"unrecognized","private":"fictional-secret"}', text=True, capture_output=True)
        self.assertEqual(json.loads(result.stdout), {'status':'failed'})
        self.assertNotIn('fictional-secret', result.stderr)

    def test_full_comparison_retains_currency_and_quantity(self):
        response = self.replay([line('COSTCO CAD'), line('SOAP 2 X 2.00 4.00', y=.5)], 'baseline')
        equal = copy.deepcopy(response)
        for item in equal['parsed']['lines']:
            item['id'] = 'different-generated-id'; item['sourceLineIDs'] = ['different-generated-evidence']
        for issue in equal['parsed']['issues']: issue['sourceLineIDs'] = ['different-evidence']
        self.assertEqual(c.full_parsed(equal), c.full_parsed(response))
        unequal = copy.deepcopy(equal); unequal['parsed']['currency'] = {'code':'USD','minorUnitScale':2}
        self.assertNotEqual(c.full_parsed(unequal), c.full_parsed(response))
        unequal = copy.deepcopy(equal); unequal['parsed']['lines'][0]['quantity'] = {'coefficient':3,'scale':0}
        self.assertNotEqual(c.full_parsed(unequal), c.full_parsed(response))

    def test_custom_labels_require_checked_schema_ids_hashes_and_store(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder); label_path = path/'custom-labels.json'
            manifest = dict(receipts=[dict(id='fictional', sha256='fictional-hash')])
            (path/'manifest.json').write_text(json.dumps(manifest))
            group = dict(purchase_id='fictional', store='Costco', images=[dict(sha256='fictional-hash')])
            label = dict(id='fictional', sha256='fictional-hash', reviewed=True,
                         verification_method='human_against_original',
                         verification_checks={k:True for k in ('fields','items','amounts','adjustments')},
                         expected=dict(merchant='COSTCO', date=None, subtotal=None,total=None,lines=[]))
            def validate(changed=label, groups=None):
                label_path.write_text(json.dumps(dict(schema_version=1,receipts=[changed])))
                return c.validated_labels(label_path,path,groups or [group])
            self.assertEqual(set(validate()), {'fictional'})
            for changed in (dict(label, reviewed=False), dict(label,sha256='wrong'), dict(label,verification_checks={}), dict(label,id='different')):
                with self.assertRaises(ValueError): validate(changed)
            with self.assertRaises(ValueError): validate(groups=[dict(group,store='T&T')])
            with self.assertRaises(ValueError): validate(groups=[dict(group,images=[dict(sha256='wrong')])])

if __name__ == '__main__': unittest.main()
