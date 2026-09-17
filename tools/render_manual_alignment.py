"""Show human vs predicted timing. No model inference and no rate adjustment."""
import json
import math
from pathlib import Path
import subprocess
import cv2
import numpy as np

root=Path('build/manual-alignment')
report=json.loads((root/'report.json').read_text())
bones=[(5,6),(5,7),(7,9),(6,8),(8,10),(5,11),(6,12),(11,12),(11,13),(13,15),(12,14),(14,16)]
for case in report['cases']:
    strategy='rtmpose-rotation-global' if case['name']=='airflare' else 'rtmpose-global'
    result=next(r['result'] for r in report['results'] if r['case']==case['name'] and r['approach']==strategy)
    selected=json.loads((root/f'{case["name"]}-{strategy}-selected.json').read_text())
    captures={s:cv2.VideoCapture(case[s]) for s in ['a','b']}
    target=root/f'{case["name"]}-manual-vs-predicted.mp4'
    proc=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','bgr24','-s','1440x720','-r','24','-i','-','-an','-c:v','libx264','-crf','19','-pix_fmt','yuv420p',str(target)],stdin=subprocess.PIPE)
    for i in range(math.ceil(case['a_end']/case['a_rate']*24)):
        elapsed=i/24; tiles=[]
        for side,rate,start,kind in [
            ('a',case['a_rate'],0,'MANUAL A'),('b',case['reference_b_rate'],case['b_start'],'MANUAL B'),
            ('a',case['a_rate'],0,'PREDICT A'),('b',result['b_rate'],result['b_start'],'PREDICT B')]:
            t=start+elapsed*rate; cap=captures[side]
            cap.set(cv2.CAP_PROP_POS_MSEC,t*1000); ok,frame=cap.read()
            tile=np.zeros((720,360,3),np.uint8)
            if ok and t<=case['a_end' if side=='a' else 'b_end']:
                h,w=frame.shape[:2]; scale=min(360/w,620/h); nw,nh=round(w*scale),round(h*scale)
                x=(360-nw)//2; y=85+(620-nh)//2
                tile[y:y+nh,x:x+nw]=cv2.resize(frame,(nw,nh))
                sample=min(selected[side],key=lambda f:abs(f['t']-t))
                person=sample['person']
                if person and abs(sample['t']-t)<.08:
                    p=person['points']
                    def pos(j): return round(x+p[j][0]*scale),round(y+p[j][1]*scale)
                    for a,b in bones:
                        if min(p[a][2],p[b][2])>=.3: cv2.line(tile,pos(a),pos(b),(0,255,0),2,cv2.LINE_AA)
            cv2.putText(tile,kind,(8,24),cv2.FONT_HERSHEY_SIMPLEX,.62,(255,255,255),1,cv2.LINE_AA)
            cv2.putText(tile,f'start {start:.3f}s / {rate:.3f}x',(8,48),cv2.FONT_HERSHEY_SIMPLEX,.48,(255,255,255),1,cv2.LINE_AA)
            cv2.putText(tile,f'source {t:.2f}s',(8,72),cv2.FONT_HERSHEY_SIMPLEX,.44,(200,200,200),1,cv2.LINE_AA)
            tiles.append(tile)
        combined=np.hstack(tiles)
        if i==24: cv2.imwrite(str(root/f'{case["name"]}-tracking-preview.jpg'),combined)
        proc.stdin.write(combined.tobytes())
    proc.stdin.close()
    if proc.wait(): raise RuntimeError('Encoding failed')
    for cap in captures.values(): cap.release()
    print(target)
