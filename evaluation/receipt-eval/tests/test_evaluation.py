import importlib.util
import json
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('evaluate',Path(__file__).resolve().parents[1]/'evaluate.py')
e=importlib.util.module_from_spec(spec);spec.loader.exec_module(e)
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from score_raw import normalize_raw

def rows(text): return [{'id':i,'text':line} for i,line in enumerate(text.splitlines())]
def claim(v, q=None): return {'value':v,'quote':q if q is not None else v}

class EvaluationTests(unittest.TestCase):
    def test_golden_text_corpus_and_repeatability(self):
        for fixture in json.loads((Path(__file__).resolve().parents[1]/'fixtures/golden.json').read_text()):
            with self.subTest():
                got=e.parse(rows(fixture['text']))
                self.assertEqual(e.score(got,fixture['expected'])['correction_operations'],0)
                self.assertTrue(e.reconciliation(got)['matches'])
                self.assertEqual(got,e.parse(rows(fixture['text'])))
    def test_minor_units_signs_bounds_and_malformed(self):
        for token, amount in [('0.01',1),('12.34',1234),('-2.00',-200),('2.00-',-200),('$3.00',300)]:self.assertEqual(e.cents(token),amount)
        for value in ['1.2','NaN','1e3','1,23','-1.00-',None,'12345678.00']:
            with self.assertRaises(ValueError):e.cents(value)
    def test_grounded_claims_and_money_token_boundary(self):
        proposal={'merchant':claim('COSTCO'),'date':claim('2026-10-07'),'subtotal':claim(''), 'total':claim('11.00','TOTAL 11.00'),'lines':[{'kind':'purchase','description':claim('APPLE','APPLE 11.00'),'amount':claim('11.00','APPLE 11.00'),'quantity':claim('')}]}
        evidence=rows('COSTCO\n2026-10-07\nAPPLE 11.00\nTOTAL 11.00')
        got=e.validate_proposal(proposal,evidence)
        self.assertEqual(got['total'],1100);self.assertFalse(got['warnings'])
        proposal['lines'][0]['amount']=claim('1.00','APPLE 11.00')
        self.assertFalse(e.validate_proposal(proposal,evidence)['lines'])
        proposal['total']=claim('12.00','TOTAL 12.00')
        self.assertIsNone(e.validate_proposal(proposal,evidence)['total'])
    def test_malformed_model_schema(self):
        for malformed in [None,[],{}, {'merchant':'text'}, {'merchant':{},'date':{},'subtotal':{},'total':{},'lines':None}]:
            self.assertTrue(e.validate_proposal(malformed,[])['warnings'])
    def test_unavailable_outputs_have_full_correction_burden(self):
        expected={'merchant':'COSTCO','date':'2026-10-07','subtotal':100,'total':100,'lines':[{'kind':'purchase','description':'APPLE','amount':100,'quantity':None}]}
        scored=e.score(e.empty_receipt(),expected)
        self.assertEqual(scored['omitted_lines'],1);self.assertEqual(scored['correction_operations'],5)
    def test_omissions_inventions_duplicates_and_amount_errors(self):
        expected={'merchant':None,'date':None,'subtotal':None,'total':None,'lines':[{'kind':'purchase','description':'APPLE','amount':100,'quantity':None}]*2}
        actual=e.empty_receipt();actual['lines']=[{'kind':'purchase','description':'APPLE','amount':101,'quantity':None},{'kind':'purchase','description':'PEAR','amount':100,'quantity':None}]
        counts=e.score(actual,expected)
        self.assertEqual(counts['omitted_lines'],1);self.assertEqual(counts['invented_lines'],1);self.assertEqual(counts['amount_corrections'],1)
    def test_geometry_merges_price_with_its_row(self):
        observations=[{'id':0,'text':'APPLE','x':0.1,'y':0.8,'width':0.3,'height':0.02},{'id':1,'text':'1.00','x':0.8,'y':0.801,'width':0.1,'height':0.02},{'id':2,'text':'TOTAL 1.00','x':0.1,'y':0.7,'width':0.8,'height':0.02}]
        got=e.group_rows(observations)
        self.assertEqual(got[0]['text'],'APPLE 1.00');self.assertEqual(got[0]['observation_ids'],[0,1])
    def test_ground_truth_schema_and_private_path(self):
        with self.assertRaises(ValueError):e.validate_expected({'merchant':'COSTCO'})
        with self.assertRaises(ValueError):e.within_private(Path('/tmp/receipt.json'))
        expected={**{f:None for f in e.FIELDS},'lines':[]};expected['total']=True
        with self.assertRaises(ValueError):e.validate_expected(expected)
    def test_unit_price_cannot_be_used_as_extension(self):
        p={'merchant':claim(''), 'date':claim(''), 'subtotal':claim(''), 'total':claim(''), 'lines':[{'kind':'purchase','description':claim('SOAP','SOAP 2 X 2.00 4.00'),'amount':claim('2.00','SOAP 2 X 2.00 4.00'),'quantity':claim('')}]}
        result=e.validate_proposal(p,rows('SOAP 2 X 2.00 4.00'))
        self.assertFalse(result['lines']);self.assertIn('line_not_printed_line_extension',result['warnings'])
    def test_review_requires_explicit_checks_and_escapes_drafts(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            run=Path(folder);(run/'results').mkdir()
            receipt=e.empty_receipt();receipt['merchant']='</script><script>untrusted</script>'
            e.write_json(run/'results/r001-A.json',{'receipt':receipt})
            e.make_review(run,{'receipts':[{'id':'r001','sha256':'synthetic','image':'/tmp/synthetic.png'}]})
            page=(run/'review.html').read_text()
            self.assertEqual(page.count('</script>'),1)
            self.assertIn(r'\u003c/script\u003e',page)
            self.assertIn('Unverified',page);self.assertIn('BigInt(a)',page)
            self.assertIn('Open original HEIC/image',page)
            self.assertIn("['adjustments'",page)
    def test_unknown_reference_fields_and_quantities_are_unscored(self):
        expected={**{f:None for f in e.FIELDS},'lines':[{'kind':'purchase','description':'APPLE','amount':100,'quantity':None}]}
        actual={'merchant':'SYNTHETIC','date':'2026-10-07','subtotal':100,'total':100,'lines':[{'kind':'purchase','description':'APPLE','amount':100,'quantity':'1 KG'}]}
        counts=e.score(actual,expected)
        self.assertEqual(counts['field_corrections'],0);self.assertEqual(counts['unexpected_fields'],0)
        self.assertEqual(counts['quantity_corrections'],0);self.assertEqual(counts['correction_operations'],0)
        for f in e.FIELDS:self.assertEqual(counts[f+'_expected'],0)
    def test_repeatability_separates_success_from_matching_failures(self):
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            run=Path(folder)
            e.write_json(run/'manifest.json',{'corpus_kind':'synthetic','environment':{},'receipts':[{'id':'r001','retailer':'No Frills'},{'id':'r002','retailer':'Costco'}]})
            for rid,status in [('r001','worker_timeout'),('r002','ok')]:
                for suffix in ('','-repeat'):
                    e.write_json(run/'results'/f'{rid}-A{suffix}.json',{'status':status,'receipt':e.empty_receipt(),'end_to_end_ms':1})
            report=e.summary(run)['approaches']['A']
            self.assertEqual(report['repeat_pairs'],2)
            self.assertEqual(report['repeat_success_pairs'],1)
            self.assertEqual(report['repeat_success_output_equal'],1)
            self.assertEqual(report['repeat_same_failure'],1)
            self.assertEqual(report['repeat_failed_pairs'],1)
    def test_raw_research_scores_do_not_imply_source_acceptance(self):
        proposal={'merchant':claim('SYNTHETIC','made up quote'),'date':claim(''),'subtotal':claim(''),'total':claim('1.00','made up quote'),'lines':[{'kind':'purchase','description':claim('APPLE','made up quote'),'amount':claim('1.00','made up quote'),'quantity':claim('')}]}
        raw=normalize_raw(proposal);accepted=e.validate_proposal(proposal,[])
        self.assertEqual(raw['total'],100);self.assertEqual(len(raw['lines']),1)
        self.assertIsNone(accepted['total']);self.assertFalse(accepted['lines'])
        proposal['lines'][0]['amount']=claim('NaN')
        self.assertIsNone(normalize_raw(proposal)['lines'][0]['amount'])
    def test_missing_total_is_not_reconciliation_success(self):
        self.assertEqual(e.reconciliation(e.empty_receipt()),{'eligible':False,'matches':False})

if __name__=='__main__':unittest.main()
