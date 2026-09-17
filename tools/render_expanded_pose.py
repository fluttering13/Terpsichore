"""Render architecture/variant skeleton grids and human/predicted timing."""
import argparse
import json
import math
import subprocess
from pathlib import Path
import cv2
import numpy as np
from benchmark_pose_candidates import BONES
from benchmark_expanded_pose import NAMES

ROOT=Path('build/pose-expanded')
# Manual visual review of these pinned fixtures, 2026-09-18, source B 1.5/3s.
# Re-review if fixtures, weights or tracking change; not an automatic metric.
IDENTITY_REVIEW={'blazepose','movenet-lightning','movenet-thunder'}

def writer(path,w,h):
    return subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','bgr24',
        '-s',f'{w}x{h}','-r','24','-i','-','-an','-c:v','libx264','-preset','fast',
        '-threads','4','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(path)],stdin=subprocess.PIPE)

def tile(frame, samples, t, title, subtitle, w=320,h=560,threshold=.3,processing_label='no smoothing'):
    canvas=np.zeros((h,w,3),np.uint8)
    if frame is not None:
        if isinstance(frame,tuple):frame,iw,ih=frame
        else:ih,iw=frame.shape[:2]
        scale=min(w/iw,(h-85)/ih)
        nw,nh=round(iw*scale),round(ih*scale); x=(w-nw)//2; y=80+(h-85-nh)//2
        canvas[y:y+nh,x:x+nw]=cv2.resize(frame,(nw,nh))
        sample=min(samples,key=lambda f:abs(f['t']-t)); person=sample['person']
        if person and abs(sample['t']-t)<=1/12:
            points=person['points']
            def pos(j):return round(x+points[j][0]*scale),round(y+points[j][1]*scale)
            inferred=person.get('inferred',[False]*17)
            for a,b in BONES:
                if min(points[a][2],points[b][2])>=threshold:cv2.line(canvas,pos(a),pos(b),(0,160,255) if inferred[a] or inferred[b] else (0,255,0),2,cv2.LINE_AA)
            for j,p in enumerate(points[:17]):
                if p[2]>=threshold:cv2.circle(canvas,pos(j),3,(0,210,255),-1,cv2.LINE_AA)
    for index,text in enumerate([title,subtitle,f'source {t:.2f}s | {processing_label}']):
        cv2.putText(canvas,text,(7,21+23*index),cv2.FONT_HERSHEY_SIMPLEX,.43,(255,255,255),1,cv2.LINE_AA)
    return canvas

class VideoCache:
    """Decode once, retain panel-sized RGB geometry plus original coordinates."""
    def __init__(self,path):
        cap=cv2.VideoCapture(path);self.fps=cap.get(cv2.CAP_PROP_FPS);self.frames=[]
        assert self.fps>0
        while True:
            ok,frame=cap.read()
            if not ok:break
            h,w=frame.shape[:2];scale=min(320/w,475/h)
            self.frames.append((cv2.resize(frame,(round(w*scale),round(h*scale))),w,h))
        cap.release()
        assert self.frames,path

    def release(self):pass

def read(cap,t,end):
    if t>end:return None
    if isinstance(cap,VideoCache):
        index=int(round(t*cap.fps))
        return cap.frames[index] if 0<=index<len(cap.frames) else None
    cap.set(cv2.CAP_PROP_POS_MSEC,t*1000);ok,frame=cap.read()
    return frame if ok else None

def finish(proc):
    proc.stdin.close()
    if proc.wait():raise RuntimeError('ffmpeg failed')

def main():
    cv2.setNumThreads(1)
    parser=argparse.ArgumentParser()
    parser.add_argument('--group',choices=['standard','diverse'],default='diverse')
    args=parser.parse_args()
    names=NAMES[:10] if args.group=='standard' else NAMES[10:]
    columns=5
    height=1120 if args.group=='standard' else 560
    report=json.loads((ROOT/'report.json').read_text())
    for case in report['cases']:
        cached={s:VideoCache(case[s]) for s in ['a','b']}
        for mode in (['raw','rot4'] if case['name']=='airflare' else ['raw']):
            rows=[next(r for r in report['results'] if r['case']==case['name'] and r['model']==n and r['mode']==mode) for n in names]
            selections=[json.loads((ROOT/f'{case["name"]}-{n}-{mode}-selected.json').read_text()) for n in names]
            for side in ['a','b']:
                target=ROOT/f'{case["name"]}-{side}-{mode}-{args.group}-models.mp4'
                proc=writer(target,columns*320,height);cap=cached[side]
                # Half speed to make missing/incorrect joints easier to inspect.
                for i in range(math.ceil(case[side+'_end']/.5*24)):
                    t=i/24*.5;frame=read(cap,t,case[side+'_end']);tiles=[]
                    for name,row,selected in zip(names,rows,selections):
                        ms=row['timings'][side]['pipeline_frame']['p50_ms']
                        tiles.append(tile(frame,selected[side],t,name,f'{mode} CPU pipeline {ms:.0f}ms'))
                    combined=np.vstack([np.hstack(tiles[start:start+columns]) for start in range(0,len(tiles),columns)])
                    if i==24:cv2.imwrite(str(target.with_suffix('.jpg')),combined)
                    proc.stdin.write(combined.tobytes())
                finish(proc);cap.release();print(target,flush=True)
            # One convenient per-case video: each model gets its own labelled section.
            target=ROOT/f'{case["name"]}-{mode}-{args.group}-alignment-comparison.mp4'
            proc=writer(target,1280,560)
            captures=cached
            for name,row,selected in zip(names,rows,selections):
                result=row['result']
                for i in range(math.ceil(case['a_end']/case['a_rate']*24)):
                    elapsed=i/24;panels=[]
                    for side,rate,start,label in [('a',case['a_rate'],0,'MANUAL A'),
                        ('b',case['reference_b_rate'],case['b_start'],'MANUAL B'),
                        ('a',case['a_rate'],0,'PREDICT A'),
                        ('b',result['b_rate'] if result else 0,result['b_start'] if result else 0,'PREDICT B')]:
                        t=start+elapsed*rate
                        frame=read(captures[side],t,case[side+'_end']) if result or label!='PREDICT B' else None
                        subtitle=f'{label} {start:.2f}s / {rate:.3f}x'
                        if not result and label=='PREDICT B':subtitle='NO VALID ALIGNMENT'
                        panels.append(tile(frame,selected[side],t,name,subtitle))
                    combined=np.hstack(panels)
                    warning='NO VALID ALIGNMENT' if not result else ('UNRELIABLE: overlap boundary' if result['warning'].startswith('near_') else 'EXPERIMENTAL - not validated')
                    if case['name']=='choreo' and name in IDENTITY_REVIEW:
                        warning='VISUAL REVIEW: cross-person pose / identity mixing - not valid target alignment'
                    cv2.putText(combined,warning,(8,552),cv2.FONT_HERSHEY_SIMPLEX,.5,(0,180,255),1,cv2.LINE_AA)
                    proc.stdin.write(combined.tobytes())
            finish(proc)
            for cap in captures.values():cap.release()
            print(target,flush=True)

if __name__=='__main__':main()
