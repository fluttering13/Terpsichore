"""Experimental CPU benchmark; never installs an app or fits to reference rates.
The reference B rates are read ONLY when reporting error after search.
Reuses pinned ONNX models/decoders from benchmark_pose_candidates.py.
"""
import json
import math
import time
from pathlib import Path
import cv2
import numpy as np
from scipy.optimize import linear_sum_assignment
from benchmark_pose_candidates import load, yolo, rtm, restore, area, iou

OUT = Path('build/manual-alignment')
OUT.mkdir(parents=True, exist_ok=True)
CASES = [
    dict(name='airflare', a='build/pose-user-a.mp4', b='build/manual-airflare-b.mp4',
         a_end=1.3, b_start=0., b_end=4.2, a_rate=.35, reference_b_rate=.9),
    dict(name='choreo', a='build/manual-choreo-a.mp4', b='build/manual-choreo-b.mp4',
         a_end=5.7, b_start=1.2, b_end=7.2, a_rate=1., reference_b_rate=1.),
]

def histogram(image, box):
    h,w=image.shape[:2]
    x1,y1,x2,y2=np.round(box).astype(int)
    crop=image[max(0,y1):min(h,y2),max(0,x1):min(w,x2)]
    if not crop.size: return np.zeros(128,np.float32)
    hsv=cv2.cvtColor(crop,cv2.COLOR_BGR2HSV)
    hist=cv2.calcHist([hsv],[0,1],None,[16,8],[0,180,0,256]).flatten()
    return hist/max(hist.sum(),1)

def extract(path, end, models, rotate):
    cap=cv2.VideoCapture(path)
    result=[]
    total_start=time.perf_counter()
    for t in np.arange(0,end+1e-6,1/12):
        cap.set(cv2.CAP_PROP_POS_MSEC,float(t)*1000)
        ok,image=cap.read()
        if not ok: break
        h,w=image.shape[:2]
        candidates=[]
        tic=time.perf_counter()
        for k in ([0,1,2,3] if rotate else [0]):
            frame=np.ascontiguousarray(np.rot90(image,k))
            detections,_=yolo(models['yolo11s-pose'],frame)
            # Limit compute; retain multiple people instead of first-frame-largest only.
            for box,yp in sorted(detections,key=lambda p:area(p[0]),reverse=True)[:5]:
                points,_=rtm(models['rtmpose-s'],frame,box)
                wb=None
                if k==0:
                    wb,_=rtm(models['rtmpose-m-wholebody'],frame,box)
                box,points=restore((box,points),k,h,w)
                candidates.append(dict(box=box,points=points,wholebody=wb,
                    rotation=k,hist=histogram(image,box),area=area(box)/(h*w)))
        result.append(dict(t=float(t),width=w,height=h,candidates=candidates,
                           pipeline_ms=(time.perf_counter()-tic)*1000))
    cap.release()
    print(path, 'frames',len(result),'seconds',round(time.perf_counter()-total_start,2),flush=True)
    return result

def quality(candidate):
    return float(np.clip(candidate['points'][5:17,2],0,1).mean())

def baseline(frames):
    selected=[]; previous=None; initial=None
    for f in frames:
        options=[c for c in f['candidates'] if c['rotation']==0]
        if previous is None:
            pick=max(options,key=lambda c:c['area']) if options else None
        else:
            options=[c for c in options if area(c['box'])>=area(initial['box'])*.3
                     and .35<=area(c['box'])/max(area(previous['box']),1)<=3
                     and iou(c['box'],previous['box'])>=.1]
            pick=max(options,key=lambda c:iou(c['box'],previous['box'])) if options else None
        selected.append(pick)
        if pick is not None:
            previous=pick
            if initial is None: initial=pick
    return selected

def global_track(frames, rotation=False):
    # Lightweight appearance + IoU Hungarian tracklets, NOT a BoT-SORT implementation.
    tracks=[]
    for index,f in enumerate(frames):
        candidates=sorted([c for c in f['candidates'] if rotation or c['rotation']==0],key=quality,reverse=True)
        detections=[]
        for c in candidates:
            if not any(iou(c['box'],p['box'])>.5 for p in detections): detections.append(c)
        active=[t for t in tracks if f['t']-t['last_time']<=.75]
        cost=np.full((len(active),len(detections)),10.)
        for i,track in enumerate(active):
            previous=track['last']
            for j,c in enumerate(detections):
                overlap=iou(previous['box'],c['box'])
                appearance=cv2.compareHist(previous['hist'],c['hist'],cv2.HISTCMP_BHATTACHARYYA)
                if overlap>=.05 and .25<=area(c['box'])/max(area(previous['box']),1)<=4:
                    cost[i,j]=.65*(1-overlap)+.35*appearance
        used=set()
        if cost.size:
            for i,j in zip(*linear_sum_assignment(cost)):
                if cost[i,j]>.8: continue
                track=active[i]; c=detections[j]; used.add(j)
                track['samples'][index]=c; track['last']=c; track['last_time']=f['t']
        for j,c in enumerate(detections):
            if j not in used: tracks.append(dict(samples={index:c},last=c,last_time=f['t']))
    if not tracks: return [None]*len(frames)
    def score(t):
        values=list(t['samples'].values())
        return len(values)/len(frames)*(.6+.3*np.mean([math.sqrt(c['area']) for c in values])+.1*np.mean([quality(c) for c in values]))
    winner=max(tracks,key=score)
    selected=[winner['samples'].get(i) for i in range(len(frames))]
    if not rotation: return selected
    # Sequence-level orientation selection within the chosen person's boxes.
    options=[]
    for f,p in zip(frames,selected):
        options.append([c for c in f['candidates'] if p is not None and iou(c['box'],p['box'])>.3] or [None])
    scores=[]; parents=[]
    for i,opts in enumerate(options):
        values=[]; links=[]
        for c in opts:
            emission=quality(c) if c is not None else -.5
            if i==0: values.append(emission); links.append(-1); continue
            transitions=[]
            for j,p in enumerate(options[i-1]):
                penalty=0
                if c is not None and p is not None:
                    valid=(c['points'][:,2]>.3)&(p['points'][:,2]>.3)
                    if valid.sum()>=4:
                        penalty=min(1.,np.median(np.linalg.norm(c['points'][valid,:2]-p['points'][valid,:2],axis=1))/max(math.sqrt(area(c['box'])),1))
                    penalty+=.08*(c['rotation']!=p['rotation'])
                transitions.append(scores[-1][j]-penalty)
            best=int(np.argmax(transitions)); values.append(emission+transitions[best]); links.append(best)
        scores.append(values); parents.append(links)
    k=int(np.argmax(scores[-1])); path=[]
    for i in range(len(options)-1,-1,-1): path.append(options[i][k]); k=parents[i][k]
    return list(reversed(path))

def features(frames, picks, wholebody=False, bones=False):
    rows=[]
    for f,c in zip(frames,picks):
        if c is None: rows.append(None); continue
        points=c['wholebody'] if wholebody else c['points']
        if points is None: rows.append(None); continue
        p=points[:17].copy()
        if bones:
            descriptor=[]
            for left,right in [(5,6),(5,7),(7,9),(6,8),(8,10),(5,11),(6,12),(11,12),(11,13),(13,15),(12,14),(14,16)]:
                vector=p[right,:2]-p[left,:2]
                length=np.linalg.norm(vector)
                score=min(p[left,2],p[right,2]) if length>1 else 0
                descriptor.append([*(vector/max(length,1)),score])
            rows.append(np.array(descriptor))
            continue
        # Same feature representation in every approach; no fitted per-case weights.
        if min(p[[5,6,11,12],2])<.3: rows.append(None); continue
        center=(p[11,:2]+p[12,:2])/2
        shoulder=(p[5,:2]+p[6,:2])/2
        scale=np.linalg.norm(center-shoulder)
        if scale<.025*f['height']: rows.append(None); continue
        p[:,:2]=(p[:,:2]-center)/scale
        rows.append(p[5:17])
    return np.array([f['t'] for f in frames]),rows

def sample(sequence, times):
    ts,rows=sequence
    result=np.full((len(times),12,3),np.nan)
    for i,t in enumerate(times):
        r=int(np.searchsorted(ts,t)); l=max(0,r-1); r=min(len(ts)-1,r)
        if t<ts[0] or t>ts[-1] or rows[l] is None or rows[r] is None: continue
        dt=ts[r]-ts[l]
        if dt>.25: continue
        alpha=(t-ts[l])/dt if dt else 0
        result[i,:,:2]=(1-alpha)*rows[l][:,:2]+alpha*rows[r][:,:2]
        result[i,:,2]=np.minimum(rows[l][:,2],rows[r][:,2])
    return result

def search(a,b,case):
    duration=case['a_end']/case['a_rate']
    timeline=np.linspace(0,duration,60,endpoint=False)+duration/120
    af=sample(a,timeline*case['a_rate'])
    radius=.1*(case['b_end']-case['b_start'])
    def evaluate(start,rate):
        source=start+timeline*rate
        inside=(source>=case['b_start'])&(source<=case['b_end'])
        if inside.mean()<.8: return None
        # Require enough B coverage without enforcing equal playback durations.
        if min(duration*rate,case['b_end']-start)<.6*(case['b_end']-case['b_start']): return None
        bf=sample(b,source)
        mask=(af[:,:,2]>=.3)&(bf[:,:,2]>=.3)&inside[:,None]
        valid_frames=mask.sum(1)>=6
        coverage=float(valid_frames.mean())
        if coverage<.5: return None
        mask &= valid_frames[:,None]
        delta=np.linalg.norm(af[:,:,:2]-bf[:,:,:2],axis=-1)
        w=np.minimum(af[:,:,2],bf[:,:,2])
        position=float(np.sum(np.minimum(delta[mask],2)*w[mask])/np.sum(w[mask]))
        direction_mask=mask[1:]&mask[:-1]
        da=np.diff(af[:,:,:2],axis=0); db=np.diff(bf[:,:,:2],axis=0)
        norm=np.linalg.norm(da,axis=-1)*np.linalg.norm(db,axis=-1)
        direction_mask &= norm>1e-4
        direction=float(np.mean(1-np.clip(np.sum(da*db,axis=-1)[direction_mask]/norm[direction_mask],-1,1))) if direction_mask.any() else 1
        return dict(b_start=round(float(start),4),b_rate=round(float(rate),4),coverage=round(coverage,3),loss=position+.2*direction+.5*(1-coverage))
    candidates=[]
    for start in np.arange(max(0,case['b_start']-radius),case['b_start']+radius+1e-8,.05):
        for rate in np.arange(.1,4.0001,.05):
            result=evaluate(start,rate)
            if result: candidates.append(result)
    if not candidates: return None
    candidates.sort(key=lambda c:c['loss'])
    seeds=[]
    for c in candidates:
        if not any(abs(c['b_rate']-s['b_rate'])<.1 and abs(c['b_start']-s['b_start'])<.1 for s in seeds): seeds.append(c)
        if len(seeds)==5: break
    for seed in seeds:
        for start in np.arange(max(0,case['b_start']-radius,seed['b_start']-.05),min(case['b_start']+radius,seed['b_start']+.05)+1e-8,.01):
            for rate in np.arange(max(.1,seed['b_rate']-.05),min(4,seed['b_rate']+.05)+1e-8,.005):
                result=evaluate(start,rate)
                if result: candidates.append(result)
    candidates.sort(key=lambda c:c['loss'])
    best=candidates[0]
    # Reference is deliberately accessed only AFTER inference and optimization.
    best['reference_b_rate']=case['reference_b_rate']
    best['absolute_rate_error']=round(abs(best['b_rate']-case['reference_b_rate']),4)
    best['relative_rate_error']=round(best['absolute_rate_error']/case['reference_b_rate'],4)
    best['reference_b_start']=case['b_start']
    best['start_error_seconds']=round(best['b_start']-case['b_start'],4)
    best['mean_mapping_error_b_source_seconds']=round(float(np.mean(np.abs(
        best['b_start']-case['b_start']+timeline*(best['b_rate']-case['reference_b_rate'])))),4)
    span=min(duration*best['b_rate'],case['b_end']-best['b_start'])/(case['b_end']-case['b_start'])
    best['b_span_coverage']=round(span,4)
    best['warning']='near_minimum_overlap_boundary_not_reliable' if span<.62 else 'experimental_not_validated'
    return best

def serial(candidate):
    if candidate is None: return None
    return {k:(v.tolist() if isinstance(v,np.ndarray) else v) for k,v in candidate.items()}

def main():
    models={name:load(name)[0] for name in ['yolo11s-pose','rtmpose-s','rtmpose-m-wholebody']}
    report=[]
    for case in CASES:
        frames=[]
        for side,end in [('a',case['a_end']),('b',case['b_end'])]:
            cache=OUT/f'{case["name"]}-{side}-candidates.json'
            if cache.exists():
                fs=json.loads(cache.read_text())
                for f in fs:
                    for c in f['candidates']:
                        for key in ['box','points','hist','wholebody']:
                            if c[key] is not None: c[key]=np.array(c[key],dtype=np.float32)
            else:
                fs=extract(case[side],end,models,rotate=case['name']=='airflare')
                cache.write_text(json.dumps([{**f,'candidates':[serial(c) for c in f['candidates']]} for f in fs]))
            frames.append(fs)
        strategies=['rtmpose-local','rtmpose-global','wholebody-global','rtmpose-bones-global']
        if case['name']=='airflare': strategies.extend(['rtmpose-rotation-global','rtmpose-rotation-bones-global'])
        for strategy in strategies:
            picks=[baseline(fs) if strategy=='rtmpose-local' else global_track(fs,rotation='rotation' in strategy) for fs in frames]
            seq=[features(fs,ps,wholebody=strategy=='wholebody-global',bones='bones' in strategy) for fs,ps in zip(frames,picks)]
            prediction=search(seq[0],seq[1],case)
            row=dict(case=case['name'],approach=strategy,result=prediction,
                     feature_frames=[sum(p is not None for p in s[1]) for s in seq],frames=[len(fs) for fs in frames])
            report.append(row)
            (OUT/f'{case["name"]}-{strategy}-selected.json').write_text(json.dumps({side:[dict(t=f['t'],person=serial(p)) for f,p in zip(fs,ps)] for side,fs,ps in zip(['a','b'],frames,picks)}))
            print(json.dumps(row),flush=True)
        (OUT/'report.json').write_text(json.dumps(dict(cases=CASES,results=report),indent=2))

if __name__=='__main__': main()
