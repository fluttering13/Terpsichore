"""ONNX adapters for distinct pose architectures, without temporal filtering.

ViTPose uses transformers 4.49.0's official UDP/DARK image processor.
MoveNet: RGB int32 NHWC 0..255, normalized y/x/score output.
BlazePose contracts follow OpenCV Zoo's mp_persondet.py and mp_pose.py;
use a single affine ROI warp and standard SSD anchor generation.
"""
import time
from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
from benchmark_pose_candidates import run

NAMES=['vitpose-small','movenet-lightning','movenet-thunder','blazepose','hrnet-w32']
COCO_FROM_BLAZE=[0,2,5,7,8,11,12,13,14,15,16,23,24,25,26,27,28]

def load(name):
    options=ort.SessionOptions();options.intra_op_num_threads=2;options.inter_op_num_threads=1
    path=Path('build/pose-candidates')/(name+'.onnx')
    start=time.perf_counter()
    model=ort.InferenceSession(str(path),options,providers=['CPUExecutionProvider'])
    info=dict(load_ms=(time.perf_counter()-start)*1000,bytes=path.stat().st_size)
    feed={}
    for i in model.get_inputs():
        shape=[d if isinstance(d,int) else 1 for d in i.shape]
        feed[i.name]=np.zeros(shape,{'tensor(float)':np.float32,'tensor(int32)':np.int32,'tensor(int64)':np.int64}[i.type])
    for _ in range(3):model.run(None,feed)
    return model,info

class VitPose:
    def __init__(self):
        from transformers import VitPoseImageProcessor
        self.processor=VitPoseImageProcessor()

    def __call__(self,model,image,box):
        from transformers.models.vitpose.image_processing_vitpose import box_to_center_and_scale
        xywh=np.r_[box[:2],box[2:]-box[:2]]
        data=self.processor(images=image[:,:,::-1],boxes=[[xywh.tolist()]],return_tensors='np')['pixel_values']
        feed={i.name:(np.array([0],np.int64) if i.name=='dataset_index' else data) for i in model.get_inputs()}
        start=time.perf_counter();raw=model.run(None,feed);ms=(time.perf_counter()-start)*1000
        center,scale=box_to_center_and_scale(xywh,192,256)
        points,scores=self.processor.keypoints_from_heatmaps(raw[0],center[None],scale[None],kernel=11)
        return np.column_stack([points[0],scores[0,:,0]]),ms

def movenet(model,image,box):
    size=model.get_inputs()[0].shape[1]
    center=(box[:2]+box[2:])/2;side=max(box[2:]-box[:2])*1.25
    factor=size/max(side,1)
    matrix=np.array([[factor,0,size/2-center[0]*factor],[0,factor,size/2-center[1]*factor]],np.float32)
    crop=cv2.warpAffine(image,matrix,(size,size))
    output,ms=run(model,crop[:,:,::-1][None].astype(np.int32))
    points=output[0].reshape(17,3).copy()
    points[:,:2]=points[:,[1,0]]*side+center-side/2
    return points,ms

def hrnet(model,image,box):
    shape=model.get_inputs()[0].shape
    channels_last=shape[-1]==3
    h,w=shape[1:3] if channels_last else shape[2:4]
    center=(box[:2]+box[2:])/2;scale=(box[2:]-box[:2])*1.25
    scale=np.array([max(scale[0],scale[1]*w/h),max(scale[1],scale[0]*h/w)])
    factor=w/max(scale[0],1)
    matrix=np.array([[factor,0,w/2-center[0]*factor],[0,factor,h/2-center[1]*factor]],np.float32)
    crop=cv2.warpAffine(image,matrix,(w,h))[:,:,::-1].astype(np.float32)/255
    raw,ms=run(model,crop[None] if channels_last else crop.transpose(2,0,1)[None])
    heatmaps=raw[0][0]
    if heatmaps.shape[-1]==17:heatmaps=heatmaps.transpose(2,0,1)
    assert heatmaps.shape[0]==17,heatmaps.shape
    _,hh,ww=heatmaps.shape
    indices=heatmaps.reshape(17,-1).argmax(-1)
    points=np.column_stack([indices%ww,indices//ww]).astype(np.float32)
    scores=heatmaps.reshape(17,-1).max(-1)
    for j,(x,y) in enumerate(points.astype(int)):
        if 1<x<ww-1 and 1<y<hh-1:
            points[j]+=.25*np.sign([heatmaps[j,y,x+1]-heatmaps[j,y,x-1],heatmaps[j,y+1,x]-heatmaps[j,y-1,x]])
    points=points/[ww,hh]*scale+center-scale/2
    return np.column_stack([points,scores]),ms

def blaze_anchors():
    return np.array([[(x+.5)/grid,(y+.5)/grid]
        for grid,repeats in [(28,2),(14,2),(7,6)]
        for y in range(grid) for x in range(grid) for _ in range(repeats)],np.float32)

ANCHORS=blaze_anchors()

def blaze_detect(model,image):
    h,w=image.shape[:2];ratio=224/max(h,w);nw,nh=int(w*ratio),int(h*ratio)
    left,top=(224-nw)//2,(224-nh)//2
    canvas=np.zeros((224,224,3),np.float32)
    rgb=image[:,:,::-1].astype(np.float32)/127.5-1
    canvas[top:top+nh,left:left+nw]=cv2.resize(rgb,(nw,nh))
    raw,ms=run(model,canvas.transpose(2,0,1)[None])
    regression=next(v for v in raw if v.shape[-1]==12)[0]
    scores=1/(1+np.exp(-np.clip(next(v for v in raw if v.shape[-1]==1)[0,:,0],-80,80)))
    mask=scores>=.5;regression=regression[mask];anchors=ANCHORS[mask];scores=scores[mask]
    if not len(scores):return [],ms
    pad=np.array([left,top])/ratio
    centers=(regression[:,:2]/224+anchors)*max(h,w)-pad
    sizes=regression[:,2:4]/224*max(h,w)
    boxes=np.column_stack([centers-sizes/2,sizes])
    keep=cv2.dnn.NMSBoxes(boxes.tolist(),scores.tolist(),.5,.3)
    points=(regression[:,4:].reshape(-1,4,2)/224+anchors[:,None])*max(h,w)-pad
    return [points[i] for i in np.asarray(keep).flatten()],ms

def blaze_pose(model,image,aux):
    center=aux[0];delta=aux[1]-center;radius=np.linalg.norm(delta)
    if radius<1:return None,0
    angle=np.degrees(np.pi/2-np.arctan2(-delta[1],delta[0]))
    matrix=cv2.getRotationMatrix2D(tuple(center.astype(float)),angle,256/(2*radius))
    matrix[:,2]+=128-center
    crop=cv2.warpAffine(image,matrix,(256,256))
    raw,ms=run(model,crop[:,:,::-1][None].astype(np.float32)/255)
    presence=float(next(v for v in raw if v.shape== (1,1))[0,0])
    if presence<.5:return None,ms
    landmarks=next(v for v in raw if v.shape==(1,195)).reshape(39,5)
    landmarks=landmarks[COCO_FROM_BLAZE]
    xy=cv2.transform(landmarks[None,:,:2],cv2.invertAffineTransform(matrix))[0]
    probabilities=1/(1+np.exp(-np.clip(landmarks[:,3:],-80,80)))
    points=np.column_stack([xy,probabilities.min(1)])
    valid=points[:,2]>=.3
    if valid.sum()<3:return None,ms
    box=np.r_[xy[valid].min(0),xy[valid].max(0)]
    return (box,points),ms
