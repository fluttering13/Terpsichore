"""Multi-architecture CPU comparison on user-labelled clips. No app changes/uploads.

Raw pass has no temporal smoothing; rotation pass adds only rotations and the
same experimental track selector. Timing excludes video decode/search/render.
"""
import argparse
import hashlib
import json
import time
from pathlib import Path
import cv2
import numpy as np
import onnxruntime as ort
from benchmark_pose_candidates import load, yolo, rtm, lite, restore, area
from benchmark_manual_alignment import CASES, histogram, global_track, features, search, serial
import diverse_pose_adapters as diverse

OUT = Path('build/pose-expanded')
NAMES = ['rtmpose-s', 'rtmpose-m', 'rtmpose-l', 'rtmpose-x',
         'rtmpose-m-wholebody', 'yolo11s-pose', 'yolov8n-pose',
         'yolov8s-pose', 'yolov8m-pose', 'litepose']
NAMES += diverse.NAMES
VIT=None

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def stats(values):
    return dict(n=len(values), mean_ms=float(np.mean(values)),
                p50_ms=float(np.median(values)), p95_ms=float(np.percentile(values,95))) if values else None

def extract(name, model, detector, path, end, rotate):
    cap=cv2.VideoCapture(path)
    frames=[]
    pose_times=[]; detect_times=[]; pipeline=[]
    for t in np.arange(0,end+1e-6,1/12):
        cap.set(cv2.CAP_PROP_POS_MSEC,float(t)*1000)
        ok,image=cap.read()
        if not ok: break
        h,w=image.shape[:2]; candidates=[]
        start=time.perf_counter()
        for k in (range(4) if rotate else [0]):
            rotated=np.ascontiguousarray(np.rot90(image,k))
            if name.startswith('rtmpose') or name.startswith('movenet') or name in ['vitpose-small','hrnet-w32']:
                people,ms=yolo(detector,rotated); detect_times.append(ms)
                people=sorted(people,key=lambda p:area(p[0]),reverse=True)[:5]
                poses=[]
                for box,_ in people:
                    adapter=rtm if name.startswith('rtmpose') else (diverse.movenet if name.startswith('movenet') else (diverse.hrnet if name=='hrnet-w32' else VIT))
                    points,ms=adapter(model,rotated,box); pose_times.append(ms)
                    poses.append((box,points[:17]))
            elif name=='blazepose':
                detections,ms=diverse.blaze_detect(detector,rotated); detect_times.append(ms)
                poses=[]
                for aux in detections[:5]:
                    person,ms=diverse.blaze_pose(model,rotated,aux);pose_times.append(ms)
                    if person is not None:poses.append(person)
            else:
                poses,ms=(lite if name=='litepose' else yolo)(model,rotated)
                pose_times.append(ms)
                poses=sorted(poses,key=lambda p:area(p[0]),reverse=True)[:5]
            for person in poses:
                box,points=restore(person,k,h,w)
                candidates.append(dict(box=box,points=points,wholebody=None,
                    rotation=k,hist=histogram(image,box),area=area(box)/(h*w)))
        elapsed=(time.perf_counter()-start)*1000
        pipeline.append(elapsed)
        frames.append(dict(t=float(t),width=w,height=h,candidates=candidates))
    cap.release()
    return frames,dict(pose_call=stats(pose_times), detector_call=stats(detect_times),
                       pipeline_frame=stats(pipeline))

def main():
    global VIT
    parser=argparse.ArgumentParser()
    parser.add_argument('--models',nargs='+',choices=NAMES,default=NAMES)
    args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    detector,_=load('yolo11s-pose')
    report=dict(environment=dict(provider='CPUExecutionProvider',cpu='Intel Core i9-14900F',
        ort=ort.__version__,intra_threads=2,inter_threads=1,warmup=3,sample_fps=12),cases=CASES,results=[])
    if (OUT/'report.json').exists():
        report['results']=[r for r in json.loads((OUT/'report.json').read_text())['results'] if r['model'] not in args.models]
    script_hash=digest(__file__)+digest('tools/benchmark_pose_candidates.py')+digest('tools/benchmark_manual_alignment.py')+digest('tools/diverse_pose_adapters.py')
    for name in args.models:
        print('MODEL',name,flush=True)
        model,info=(diverse.load if name in diverse.NAMES else load)(name)
        current_detector=diverse.load('blazepose-detector')[0] if name=='blazepose' else detector
        detector_sha=digest('build/pose-candidates/'+('blazepose-detector' if name=='blazepose' else 'yolo11s-pose')+'.onnx')
        if name=='vitpose-small':VIT=diverse.VitPose()
        modelpath=Path('asset/models/litepose_s_coco.onnx') if name=='litepose' else Path('build/pose-candidates')/(name+'.onnx')
        for case in CASES:
            for rotate in ([False,True] if case['name']=='airflare' else [False]):
                mode='rot4' if rotate else 'raw'
                prefix=f'{case["name"]}-{name}-{mode}'
                signature=hashlib.sha256((script_hash+digest(modelpath)+detector_sha+
                    digest(case['a'])+digest(case['b'])+json.dumps(case,sort_keys=True)+mode).encode()).hexdigest()
                cache=OUT/(prefix+'-result.json')
                if cache.exists() and json.loads(cache.read_text())['signature']==signature:
                    row=json.loads(cache.read_text()); print('Cached',prefix,flush=True)
                else:
                    sequences=[]; selected={}; timings={}; counts=[]
                    for side in ['a','b']:
                        frames,timing=extract(name,model,current_detector,case[side],case[side+'_end'],rotate)
                        picks=global_track(frames,rotation=rotate)
                        sequences.append(features(frames,picks))
                        counts.append([sum(x is not None for x in sequences[-1][1]),len(frames)])
                        timings[side]=timing
                        selected[side]=[dict(t=f['t'],person=serial(p)) for f,p in zip(frames,picks)]
                        print(prefix,side,len(frames),'frames',round(timing['pipeline_frame']['p50_ms'],1),'ms/frame',flush=True)
                    prediction=search(*sequences,case)
                    row=dict(signature=signature,case=case['name'],model=name,mode=mode,
                             model_info=info,sha256=digest(modelpath),detector_sha256=detector_sha,timings=timings,
                             feature_frames=counts,result=prediction)
                    (OUT/(prefix+'-selected.json')).write_text(json.dumps(selected))
                    cache.write_text(json.dumps(row,indent=2))
                    print('RESULT',prefix,json.dumps(prediction),flush=True)
                report['results'].append(row)
                (OUT/'report.json').write_text(json.dumps(report,indent=2))
        del model

if __name__=='__main__': main()
