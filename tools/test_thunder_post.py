import unittest
import numpy as np
from benchmark_thunder_post import process

class PostTests(unittest.TestCase):
    def fixture(self):
        ts=np.arange(9)/12
        p=np.zeros((9,17,3));p[:,:,0]=100+ts[:,None]*10;p[:,:,1]=100+ts[:,None]*20;p[:,:,2]=.9
        boxes=[np.array([0.,0.,300.,300.]) for _ in ts]
        return ts,p,boxes

    def test_local_linear_preserves_constant_velocity_without_mutation(self):
        ts,p,boxes=self.fixture();original=p.copy()
        out,_=process(ts,p,boxes,'linear',.5,.3)
        np.testing.assert_allclose(out,p,atol=1e-8);np.testing.assert_equal(p,original)

    def test_short_gap_is_marked_but_long_gap_not_filled(self):
        ts,p,boxes=self.fixture();p[2,:,2]=0;p[5:8,:,2]=0
        out,filled=process(ts,p,boxes,'raw',0,.3,fill=True)
        self.assertTrue(filled[2].all());self.assertFalse(filled[5:8].any())
        np.testing.assert_allclose(out[2,:,2],.45)
        self.assertEqual(out[5:8,:,2].sum(),0)

    def test_box_guard_rejects_outside_joint(self):
        ts,p,boxes=self.fixture();p[4,0,:2]=[1000,1000]
        out,_=process(ts,p,boxes,'raw',0,.3,guard=True)
        self.assertEqual(out[4,0,2],0)

    def test_all_missing_stays_missing(self):
        ts,p,boxes=self.fixture();p[:,:,2]=0
        for method in ['raw','gaussian','linear','robust','median','one_euro']:
            out,filled=process(ts,p,boxes,method,.5,.15,fill=True)
            self.assertEqual(out[:,:,2].sum(),0);self.assertFalse(filled.any())

if __name__=='__main__':unittest.main()
