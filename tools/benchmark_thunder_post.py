"""Fixed MoveNet Thunder evidence; post-processing ablation, not model tuning.
Human reference rates enter evaluation only after the unchanged search.
Two examples are a development set, not a held-out accuracy benchmark.
"""
import copy
import json
import time
from pathlib import Path
import cv2
import numpy as np
from benchmark_manual_alignment import CASES, features, search

OUT=Path('build/thunder-post')
SOURCE=Path('build/pose-expanded')

def process(ts,raw,boxes,method,window,threshold,guard=False,fill=False):
    p=raw.copy(); inferred=np.zeros(p.shape[:2],bool)
    valid=np.isfinite(p).all(2)&(p[:,:,2]>=threshold)
    if guard:
        for i,box in enumerate(boxes):
            if box is None:valid[i]=False;continue
            size=box[2:]-box[:2];lo=box[:2]-.1*size;hi=box[2:]+.1*size
            valid[i]&=((p[i,:,:2]>=lo)&(p[i,:,:2]<=hi)).all(1)
        # Reject isolated temporal spikes only; do not erase sustained motion.
        for i in range(1,len(ts)-1):
            if boxes[i] is None:continue
            scale=max(np.linalg.norm(boxes[i][2:]-boxes[i][:2]),1)
            both=valid[i-1]&valid[i]&valid[i+1]
            middle=np.linalg.norm(p[i,:,:2]-(p[i-1,:,:2]+p[i+1,:,:2])/2,axis=1)/scale
            ends=np.linalg.norm(p[i-1,:,:2]-p[i+1,:,:2],axis=1)/scale
            valid[i]&=~(both&(middle>.25)&(ends<.12))
    if fill:
        for j in range(17):
            indices=np.flatnonzero(valid[:,j])
            for l,r in zip(indices,indices[1:]):
                if r-l!=2 or ts[r]-ts[l]>.2 or boxes[l] is None or boxes[r] is None:continue
                scale=max(np.linalg.norm(boxes[l][2:]-boxes[l][:2]),1)
                if np.linalg.norm(p[r,j,:2]-p[l,j,:2])>.25*scale:continue
                i=l+1;alpha=(ts[i]-ts[l])/(ts[r]-ts[l])
                p[i,j,:2]=(1-alpha)*p[l,j,:2]+alpha*p[r,j,:2]
                p[i,j,2]=min(p[l,j,2],p[r,j,2])*.5
                valid[i,j]=p[i,j,2]>=threshold;inferred[i,j]=True
    output=p.copy()
    if method=='one_euro':
        for j in range(17):
            last=None;velocity=np.zeros(2)
            for i,t in enumerate(ts):
                if not valid[i,j]:continue
                if last is not None and t-ts[last]<=.2:
                    dt=t-ts[last];scale=max(np.linalg.norm(boxes[i][2:]-boxes[i][:2]),1) if boxes[i] is not None else 1
                    a=1/(1+1/(2*np.pi*dt))
                    velocity=a*(p[i,j,:2]-p[last,j,:2])/dt+(1-a)*velocity
                    cutoff=1+2*np.linalg.norm(velocity)/scale
                    alpha=1/(1+1/(2*np.pi*cutoff*dt))
                    output[i,j,:2]=alpha*p[i,j,:2]+(1-alpha)*output[last,j,:2]
                last=i
    elif method!='raw':
        for i,t in enumerate(ts):
            for j in range(17):
                if not valid[i,j]:continue
                # Keep processing inside uninterrupted observed/short-filled runs.
                l=r=i
                while l>0 and valid[l-1,j] and ts[l]-ts[l-1]<=.2:l-=1
                while r+1<len(ts) and valid[r+1,j] and ts[r+1]-ts[r]<=.2:r+=1
                indices=np.arange(l,r+1);indices=indices[np.abs(ts[indices]-t)<=window/2+1e-8]
                if len(indices)<3:continue
                xy=p[indices,j,:2];dt=ts[indices]-t
                if method=='median':output[i,j,:2]=np.median(xy,axis=0);continue
                weights=np.exp(-.5*(dt/max(window/4,1e-6))**2)*p[indices,j,2]**2
                if method=='robust':
                    residual=np.linalg.norm(xy-np.median(xy,axis=0),axis=1)
                    scale=max(np.median(residual)*1.4826,1)
                    weights*=np.minimum(1,1.5*scale/np.maximum(residual,1e-6))
                if method in ['linear','robust']:
                    design=np.column_stack([np.ones(len(dt)),dt]);root=np.sqrt(weights)
                    output[i,j,:2]=np.linalg.lstsq(design*root[:,None],xy*root[:,None],rcond=None)[0][0]
                else:output[i,j,:2]=np.average(xy,axis=0,weights=weights)
    output[~valid,2]=0
    return output,inferred

def load(case,side):
    mode='rot4' if case['name']=='airflare' else 'raw'
    rows=json.loads((SOURCE/f'{case["name"]}-movenet-thunder-{mode}-selected.json').read_text())[side]
    cap=cv2.VideoCapture(case[side]);w=cap.get(cv2.CAP_PROP_FRAME_WIDTH);h=cap.get(cv2.CAP_PROP_FRAME_HEIGHT);cap.release()
    ts=np.array([f['t'] for f in rows]);points=np.array([f['person']['points'] if f['person'] else np.zeros((17,3)) for f in rows])
    boxes=[np.array(f['person']['box']) if f['person'] else None for f in rows]
    return rows,ts,points,boxes,w,h

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    configurations=[]
    for threshold in [.3,.2,.15]:
        for method,window in [('raw',0),('gaussian',.3),('gaussian',.5),('linear',.3),('linear',.5),('robust',.3),('robust',.5),('median',.3),('median',.5),('one_euro',0)]:
            configurations.append(dict(method=method,window=window,threshold=threshold,guard=False,fill=False))
        configurations += [dict(method='robust',window=.3,threshold=threshold,guard=True,fill=fill) for fill in [False,True]]
    cached={(c['name'],s):load(c,s) for c in CASES for s in ['a','b']}
    results=[]
    for index,config in enumerate(configurations):
        key=f'{index:02d}-{config["method"]}-w{config["window"]}-c{config["threshold"]}-g{int(config["guard"])}-f{int(config["fill"])}'
        result=dict(id=key,config=config,cases=[],development_score=0.)
        for case in CASES:
            sequences=[];selected={};post_ms=0;filled=0;counts=[]
            for side in ['a','b']:
                rows,ts,raw,boxes,w,h=cached[case['name'],side]
                start=time.perf_counter();points,inferred=process(ts,raw,boxes,**config);post_ms+=(time.perf_counter()-start)*1000;filled+=int(inferred.sum())
                frames=[];picks=[];display=[]
                for i,row in enumerate(rows):
                    frames.append(dict(t=float(ts[i]),width=w,height=h))
                    candidate=copy.deepcopy(row['person'])
                    if candidate:
                        candidate['points']=points[i].copy()
                        # Explicit threshold sensitivity: gate at chosen threshold,
                        # remap accepted confidences for the existing .3 search gate.
                        candidate['points'][:,2]=np.where(points[i,:,2]>=config['threshold'],np.maximum(points[i,:,2],.3),0)
                    picks.append(candidate)
                    display.append(dict(t=float(ts[i]),person=None if row['person'] is None else {**row['person'],'points':points[i].tolist(),'inferred':inferred[i].tolist()}))
                sequence=features(frames,picks);sequences.append(sequence);counts.append(sum(p is not None for p in sequence[1]));selected[side]=display
            prediction=search(*sequences,case)
            result['cases'].append(dict(case=case['name'],result=prediction,post_ms=post_ms,filled_joint_samples=filled,feature_frames=counts))
            result['development_score']+=1 if prediction is None else prediction['mean_mapping_error_b_source_seconds']/(case['b_end']-case['b_start'])
            (OUT/f'{case["name"]}-{key}-selected.json').write_text(json.dumps(selected))
        results.append(result);print(key,[(x['case'],x['result'] and [x['result']['b_start'],x['result']['b_rate']]) for x in result['cases']],flush=True)
        (OUT/'report.json').write_text(json.dumps(dict(cases=CASES,results=results,warning='Development-set ranking only; cached choreography predictions contain known cross-person contamination.'),indent=2))
    ranked=sorted(results,key=lambda r:r['development_score'])
    (OUT/'ranking.json').write_text(json.dumps(ranked,indent=2))
    print('NUMERIC BEST',ranked[0]['id'],ranked[0]['development_score'],flush=True)

if __name__=='__main__':main()
