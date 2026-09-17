"""Local A/B pose experiment. No uploads, no app modifications.

python tools/benchmark_pose_candidates.py A.mp4 B.mp4
Deps: numpy, opencv-python, onnxruntime (isolated export environment).
Baseline includes required decoding/NMS/AE association, not optional refinements.
Post adds four rotations, target continuity and confidence-weighted smoothing.
RTMPose uses YOLO11s boxes in BOTH runs; its total includes the detector.
No ground-truth labels: coverage and confidence are NOT accuracy metrics.
"""
import json
import platform
import sys
import time
from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort

OUT = Path('build/pose-candidates')
BONES = [(5,6),(5,7),(7,9),(6,8),(8,10),(5,11),(6,12),(11,12),(11,13),(13,15),(12,14),(14,16)]
NAMES = ['litepose','yolo11s-pose','rtmpose-s','rtmpose-m-wholebody']

def load(name):
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    options.inter_op_num_threads = 1
    options.log_severity_level = 3
    path = Path('asset/models/litepose_s_coco.onnx') if name=='litepose' else OUT/f'{name}.onnx'
    start=time.perf_counter()
    model=ort.InferenceSession(str(path),options,providers=['CPUExecutionProvider'])
    startup=(time.perf_counter()-start)*1000
    for _ in range(3):
        shape=[d if isinstance(d,int) else 1 for d in model.get_inputs()[0].shape]
        model.run(None,{model.get_inputs()[0].name:np.zeros(shape,np.float32)})
    return model,dict(load_ms=startup,bytes=path.stat().st_size)

def run(model, data):
    start=time.perf_counter()
    values=model.run(None,{model.get_inputs()[0].name:np.ascontiguousarray(data)})
    return values,(time.perf_counter()-start)*1000

def letterbox(image,size,value):
    h,w=image.shape[:2]; ratio=min(size/w,size/h)
    nw,nh=round(w*ratio),round(h*ratio)
    left,top=(size-nw)//2,(size-nh)//2
    canvas=np.full((size,size,3),value,np.uint8)
    canvas[top:top+nh,left:left+nw]=cv2.resize(image,(nw,nh))
    return canvas,ratio,np.array([left,top])

def yolo(model,image):
    canvas,ratio,pad=letterbox(image,640,114)
    raw,ms=run(model,canvas[:,:,::-1].transpose(2,0,1)[None].astype(np.float32)/255)
    rows=raw[0][0].T
    assert rows.shape[1]==56,rows.shape
    rows=rows[rows[:,4]>.25]
    if not len(rows): return [],ms
    boxes=rows[:,:4].copy(); boxes[:,:2]-=boxes[:,2:]/2
    keep=cv2.dnn.NMSBoxes(boxes.tolist(),rows[:,4].tolist(),.25,.45)
    people=[]
    for row in rows[np.asarray(keep).flatten()]:
        box=np.r_[row[:2]-row[2:4]/2,row[:2]+row[2:4]/2]
        box=(box-np.tile(pad,2))/ratio
        points=row[5:].reshape(17,3).copy(); points[:,:2]=(points[:,:2]-pad)/ratio
        people.append((box,points))
    return people,ms

def lite(model,image):
    canvas,ratio,pad=letterbox(image,448,0)
    raw,ms=run(model,canvas.transpose(2,0,1)[None].astype(np.float32))
    values=raw[0][0]; groups=[]
    for joint in [5,6,11,12,7,8,13,14,9,10,15,16,0,1,2,3,4]:
        for x,y,score,tag in values[joint]:
            if score<.15: continue
            x,y=(np.array([x,y])*448-pad)/ratio
            if not (0<=x<image.shape[1] and 0<=y<image.shape[0]): continue
            match,distance=None,1.
            for group in groups:
                if any(p[0]==joint for p in group): continue
                d=abs(np.mean([p[4] for p in group])-tag)
                if d<distance: match,distance=group,d
            point=(joint,x,y,score,tag)
            if match is None: groups.append([point])
            else: match.append(point)
    people=[]
    # Association is necessary decoding. Do not apply the app's >=8-joint
    # all-or-nothing rejection or multi-person rejection in this experiment.
    for group in groups:
        if sum(p[0]>=5 for p in group)<3: continue
        points=np.zeros((17,3),np.float32)
        for j,x,y,s,_ in group: points[j]=[x,y,min(float(s),1.)]
        valid=points[points[:,2]>=.15,:2]
        people.append((np.r_[valid.min(0),valid.max(0)],points))
    return people,ms

def rtm(model,image,box):
    _,_,h,w=model.get_inputs()[0].shape
    center=(box[:2]+box[2:])/2; scale=(box[2:]-box[:2])*1.25
    scale=np.array([max(scale[0],scale[1]*w/h),max(scale[1],scale[0]*h/w)])
    factor=w/max(scale[0],1)
    matrix=np.array([[factor,0,w/2-center[0]*factor],[0,factor,h/2-center[1]*factor]],np.float32)
    crop=cv2.warpAffine(image,matrix,(w,h))
    crop=(crop.astype(np.float32)-np.array([123.675,116.28,103.53],np.float32))/np.array([58.395,57.12,57.375],np.float32)
    raw,ms=run(model,crop.transpose(2,0,1)[None])
    sx,sy=raw
    points=np.stack([sx.argmax(-1),sy.argmax(-1)],axis=-1)[0]/2
    points=points/[w,h]*scale+center-scale/2
    scores=np.minimum(sx.max(-1),sy.max(-1))[0]
    return np.column_stack([points,scores]),ms

def area(box): return max(0,box[2]-box[0])*max(0,box[3]-box[1])

def iou(a,b):
    lo=np.maximum(a[:2],b[:2]); hi=np.minimum(a[2:],b[2:])
    inter=float(np.maximum(hi-lo,0).prod())
    return inter/max(area(a)+area(b)-inter,1)

def unrotate(points,k,h,w):
    p=points.copy(); x,y=p[:,0].copy(),p[:,1].copy()
    if k==1: p[:,0],p[:,1]=w-1-y,x
    if k==2: p[:,0],p[:,1]=w-1-x,h-1-y
    if k==3: p[:,0],p[:,1]=y,h-1-x
    return p

def restore(person,k,h,w):
    box,points=person
    corners=np.array([[box[0],box[1],1],[box[2],box[3],1]])
    corners=unrotate(corners,k,h,w)[:,:2]
    return np.r_[corners.min(0),corners.max(0)],unrotate(points,k,h,w)

def quality(person,previous):
    box,p=person
    score=float(np.clip(p[5:17,2],0,1).mean())
    if previous is not None: score+=.35*iou(box,previous[0])
    return score

def infer(models,name,image,post,previous):
    start=time.perf_counter(); inference_ms=0.; candidates=[]
    h,w=image.shape[:2]
    for k in ([0,1,2,3] if post else [0]):
        frame=np.ascontiguousarray(np.rot90(image,k))
        if name=='litepose': people,ms=lite(models[name],frame)
        else: people,ms=yolo(models['yolo11s-pose'],frame)
        inference_ms+=ms
        if not people: continue
        # Same initial largest-person rule in both passes. Post prefers spatial
        # continuity once a target exists. This is not robust re-identification.
        target=max(people,key=lambda p:area(p[0]) if previous is None or not post else iou(restore(p,k,h,w)[0],previous[0])+.1*area(p[0])/(h*w))
        if name.startswith('rtmpose'):
            points,ms=rtm(models[name],frame,target[0]); inference_ms+=ms
            target=(target[0],points)
        candidates.append(restore(target,k,h,w))
    selected=max(candidates,key=lambda p:quality(p,previous)) if candidates else None
    if post and selected is not None and previous is not None and iou(selected[0],previous[0])>.2:
        p=selected[1].copy(); old=previous[1]
        valid=(p[:,2]>=.3)&(old[:,2]>=.3)
        # Only smooth observed joints, never fill missing joints.
        p[valid,:2]=.8*p[valid,:2]+.2*old[valid,:2]
        selected=(selected[0],p)
    return selected,inference_ms,(time.perf_counter()-start)*1000

def tile(image,person,label):
    h,w=image.shape[:2]; result=cv2.resize(image,(270,480))
    if person is not None:
        p=person[1][:17].copy(); p[:,:2]*=[270/w,480/h]
        for a,b in BONES:
            if min(p[a,2],p[b,2])>=.3: cv2.line(result,tuple(p[a,:2].astype(int)),tuple(p[b,:2].astype(int)),(0,255,0),2)
        for x,y,score in p:
            if score>=.3: cv2.circle(result,(int(x),int(y)),3,(0,255,255),-1)
    cv2.rectangle(result,(0,0),(270,27),(0,0,0),-1)
    cv2.putText(result,label,(5,18),cv2.FONT_HERSHEY_SIMPLEX,.4,(255,255,255),1)
    return result

def main():
    models={}; metadata={}
    for name in NAMES: models[name],metadata[name]=load(name)
    report=[]; summaries=[]
    for clip,path in zip(['A','B'],sys.argv[1:3]):
        capture=cv2.VideoCapture(path)
        duration=capture.get(cv2.CAP_PROP_FRAME_COUNT)/capture.get(cv2.CAP_PROP_FPS)
        samples=[]
        for t in np.arange(0,duration,1/6):
            capture.set(cv2.CAP_PROP_POS_MSEC,t*1000)
            ok,frame=capture.read()
            if ok: samples.append((float(t),frame))
        capture.release()
        picks=set(np.linspace(0,len(samples)-1,5).round().astype(int))
        for name in NAMES:
            sheets=[]
            for post in [False,True]:
                previous=None; row_tiles=[]; rows=[]
                for index,(t,image) in enumerate(samples):
                    person,ms,total=infer(models,name,image,post,previous)
                    previous=person
                    points=None if person is None else person[1]
                    valid=0 if points is None else int((points[5:17,2]>=.3).sum())
                    row=dict(clip=clip,t=t,model=name,post=post,body_joints_above_03=valid,inference_ms=ms,total_ms=total,points=None if points is None else points.tolist())
                    rows.append(row); report.append(row)
                    if index in picks: row_tiles.append(tile(image,person,f'{name} {"post" if post else "raw"} {t:.2f}s'))
                summary=dict(clip=clip,model=name,post=post,frames=len(rows),frames_with_8_body_joints=sum(r['body_joints_above_03']>=8 for r in rows),median_inference_ms=round(float(np.median([r['inference_ms'] for r in rows])),1),median_total_ms=round(float(np.median([r['total_ms'] for r in rows])),1),p95_total_ms=round(float(np.percentile([r['total_ms'] for r in rows],95)),1))
                summaries.append(summary); print(json.dumps(summary),flush=True)
                sheets.append(np.hstack(row_tiles))
            cv2.imwrite(str(OUT/f'{clip}-{name}.jpg'),np.vstack(sheets))
    (OUT/'report.json').write_text(json.dumps(dict(environment=dict(platform=platform.platform(),cpu=platform.processor(),onnxruntime=ort.__version__,provider='CPUExecutionProvider',threads=2),models=metadata,summary=summaries,frames=report)),encoding='utf-8')

if __name__=='__main__': main()
