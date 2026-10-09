import copy
import unittest
from unittest.mock import patch
import compare as c

class ProtocolTests(unittest.TestCase):
    def response(self):
        return dict(observations=[dict(id='first',text='FICTIONAL TEA'),dict(id='second',text='4.00')],
                    groupedRowIDs=[['first'],['second']],interpretedRowIDs=[['first','second']],
                    parsed=dict(lines=[dict(kind='purchase',description='FICTIONAL TEA',amount=400,sourceLineIDs=['first','second'])],
                                issues=[dict(code='source_review_required',sourceLineIDs=['first','second'])]))
    def testConservedDetachedSourceMembership(self):
        c.membership(self.response())
    def testMissingInterpretationObservationRejected(self):
        r=self.response();r['interpretedRowIDs']=[['first']]
        with self.assertRaises(ValueError):c.membership(r)
    def testDuplicatedInterpretationObservationRejected(self):
        r=self.response();r['interpretedRowIDs']=[['first','second'],['second']]
        with self.assertRaises(ValueError):c.membership(r)
    def testUnrecognizedLineSourceRejected(self):
        r=self.response();r['parsed']['lines'][0]['sourceLineIDs'].append('invented')
        with self.assertRaises(ValueError):c.membership(r)
    def testDuplicatedLineSourceRejected(self):
        r=self.response();r['parsed']['lines'][0]['sourceLineIDs'].append('first')
        with self.assertRaises(ValueError):c.membership(r)
    def testReviewIssueCannotDiscardUnparsedSource(self):
        r=self.response();r['parsed']['issues'][0]['sourceLineIDs']=['first']
        with self.assertRaises(ValueError):c.membership(r)
    def testPrivateWorkerExceptionDoesNotExposeInput(self):
        with patch.object(c.a.subprocess,'run',side_effect=ValueError('PRIVATE-SENTINEL')):
            with self.assertRaisesRegex(ValueError,'^private_worker_failed$'):
                c.a.capture_worker('/tmp/unused',dict(image='PRIVATE-SENTINEL'))
    def testQuantityRepresentationDoesNotClaimQuantityAccuracy(self):
        r=self.response();r['parsed'].update(merchant=None,date=None,subtotal=None,total=None)
        expected=dict(merchant=None,date=None,subtotal=None,total=None,lines=[dict(kind='purchase',description='FICTIONAL TEA',amount=400,quantity='2 X 2.00')])
        r['parsed']['lines'][0]['quantity']=dict(coefficient=2,scale=0)
        score=c.a.amount_score(c.a.normalize(r),expected)
        self.assertEqual(score['item_amounts_correct'],1)
        self.assertEqual(score['quantity_corrections'],0)

if __name__=='__main__':unittest.main()
