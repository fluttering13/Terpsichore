import unittest
import numpy as np
from diverse_pose_adapters import blaze_anchors, movenet, blaze_pose, hrnet

class Input:
    name='image'
    shape=[1,192,192,3]

class FakeModel:
    def __init__(self,output):self.output=output;self.input=None
    def get_inputs(self):return [Input()]
    def run(self,_,feed):self.input=feed['image'];return self.output

class AdapterTests(unittest.TestCase):
    def test_hrnet_heatmap_center_and_rgb_range(self):
        class HRNetModel(FakeModel):
            def get_inputs(self):
                value=Input();value.shape=[1,3,256,192];return [value]
        heatmaps=np.zeros((1,17,64,48),np.float32);heatmaps[:,:,32,24]=.9
        model=HRNetModel([heatmaps])
        image=np.full((200,200,3),[10,20,30],np.uint8)
        points,_=hrnet(model,image,np.array([50,20,150,180]))
        np.testing.assert_allclose(points[:,:2],np.tile([100,100],(17,1)))
        np.testing.assert_allclose(model.input[0,:,128,96],np.array([30,20,10])/255,atol=1e-7)

    def test_anchor_layout(self):
        anchors=blaze_anchors()
        self.assertEqual(anchors.shape,(2254,2))
        np.testing.assert_allclose(anchors[0],[.5/28,.5/28])
        np.testing.assert_allclose(anchors[1568],[.5/14,.5/14])
        np.testing.assert_allclose(anchors[-1],[6.5/7,6.5/7])

    def test_movenet_rgb_dtype_and_inverse_crop(self):
        image=np.full((200,200,3),[10,20,30],np.uint8)
        output=np.tile([.5,.5,.9],(1,1,17,1)).astype(np.float32)
        model=FakeModel([output])
        points,_=movenet(model,image,np.array([50,20,150,180]))
        np.testing.assert_allclose(points[:,:2],np.tile([100,100],(17,1)))
        self.assertEqual(model.input.dtype,np.int32)
        np.testing.assert_equal(model.input[0,96,96],[30,20,10])

    def test_blaze_inverse_rotation_and_coco_mapping(self):
        image=np.zeros((300,300,3),np.uint8)
        landmarks=np.tile([128,128,0,10,10],(39,1)).astype(np.float32)
        # Knees and ankles span the ROI; center remains fixed under rotation.
        landmarks[25:29,:2]=[[100,160],[150,160],[100,220],[150,220]]
        model=FakeModel([landmarks.reshape(1,195),np.array([[.99]],np.float32)])
        for full in [[150,50],[250,150],[150,250],[50,150]]:
            person,_=blaze_pose(model,image,np.array([[150,150],full,[0,0],[0,0]],np.float32))
            self.assertIsNotNone(person)
            np.testing.assert_allclose(person[1][0,:2],[150,150],atol=1e-4)
            self.assertEqual(person[1].shape,(17,3))
            self.assertEqual(model.input.shape,(1,256,256,3))

    def test_blaze_rejects_missing_person(self):
        model=FakeModel([np.zeros((1,195)),np.array([[.1]])])
        person,_=blaze_pose(model,np.zeros((200,200,3),np.uint8),np.array([[100,100],[100,20],[0,0],[0,0]]))
        self.assertIsNone(person)

if __name__=='__main__':unittest.main()
