"""Synthetic recovery tests, independent of the two labelled clips."""
import unittest
import numpy as np
from benchmark_manual_alignment import search

def sequence(clock):
    ts=np.arange(0,6,1/12)
    return ts,[np.array([[np.sin(clock(t)*(1+j*.13)),np.cos(clock(t)*(1.7+j*.09)),.95] for j in range(12)]) for t in ts]

class SearchTest(unittest.TestCase):
    def test_recovers_independent_start_and_rate(self):
        case=dict(a_end=3.,a_rate=1.,b_start=0.,b_end=5.,reference_b_rate=.9)
        a=sequence(lambda t:t)
        b=sequence(lambda t:(t-.17)/1.17)
        result=search(a,b,case)
        self.assertIsNotNone(result)
        self.assertAlmostEqual(result['b_start'],.17,delta=.03)
        self.assertAlmostEqual(result['b_rate'],1.17,delta=.02)
        other=search(a,b,{**case,'reference_b_rate':3.})
        self.assertEqual(result['b_rate'],other['b_rate'])
        self.assertEqual(result['b_start'],other['b_start'])

    def test_missing_evidence_rejects(self):
        missing=(np.arange(0,6,1/12),[None]*72)
        self.assertIsNone(search(missing,missing,dict(a_end=3.,a_rate=1.,b_start=0.,b_end=5.,reference_b_rate=1.)))

if __name__=='__main__': unittest.main()
