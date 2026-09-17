"""Fixed raw pose vs post-process variants; predictions are experimental."""
import json
import math
from pathlib import Path
import cv2
import numpy as np
from render_expanded_pose import VideoCache,read,tile,writer,finish

root=Path('build/thunder-post')
report=json.loads((root/'report.json').read_text())
ranking=json.loads((root/'ranking.json').read_text())
ids=[report['results'][0]['id'],ranking[0]['id'],report['results'][13]['id'],report['results'][23]['id'],report['results'][21]['id']]
variants=[next(r for r in report['results'] if r['id']==key) for key in ids]
cv2.setNumThreads(1)
for case in report['cases']:
    caches={s:VideoCache(case[s]) for s in ['a','b']}
    selections=[json.loads((root/f'{case["name"]}-{v["id"]}-selected.json').read_text()) for v in variants]
    for side in ['a','b']:
        target=root/f'{case["name"]}-{side}-post-comparison.mp4';proc=writer(target,1600,560)
        for i in range(math.ceil(case[side+'_end']/.5*24)):
            t=i/24*.5;frame=read(caches[side],t,case[side+'_end']);tiles=[]
            for variant,selected in zip(variants,selections):
                c=variant['config'];title=c['method']+(' + gap fill' if c['fill'] else '')
                tiles.append(tile(frame,selected[side],t,title,f'window {c["window"]}s | conf {c["threshold"]}',threshold=c['threshold'],processing_label='POST' if c['method']!='raw' else 'RAW'))
            combined=np.hstack(tiles)
            if i==72:cv2.imwrite(str(target.with_suffix('.jpg')),combined)
            proc.stdin.write(combined.tobytes())
        finish(proc);print(target,flush=True)
    target=root/f'{case["name"]}-manual-vs-post.mp4';proc=writer(target,1280,560)
    for variant,selected in zip(variants,selections):
        c=variant['config'];result=next(x for x in variant['cases'] if x['case']==case['name'])['result']
        for i in range(math.ceil(case['a_end']/case['a_rate']*24)):
            elapsed=i/24;panels=[]
            for side,rate,start,label in [('a',case['a_rate'],0,'MANUAL A'),('b',case['reference_b_rate'],case['b_start'],'MANUAL B'),('a',case['a_rate'],0,'PREDICT A'),('b',result['b_rate'] if result else 0,result['b_start'] if result else 0,'PREDICT B')]:
                t=start+elapsed*rate;frame=read(caches[side],t,case[side+'_end']) if result or label!='PREDICT B' else None
                panels.append(tile(frame,selected[side],t,f'{c["method"]} w={c["window"]} c={c["threshold"]}',f'{label} {start:.2f}s / {rate:.3f}x' if result or label!='PREDICT B' else 'NO VALID ALIGNMENT',threshold=c['threshold'],processing_label='EXPERIMENT'))
            combined=np.hstack(panels)
            warning='DEVELOPMENT SET ONLY - not a validated alignment'
            if case['name']=='choreo':warning='KNOWN CROSS-PERSON CONTAMINATION - smoothing does not fix identity'
            cv2.putText(combined,warning,(8,552),cv2.FONT_HERSHEY_SIMPLEX,.48,(0,160,255),1,cv2.LINE_AA)
            proc.stdin.write(combined.tobytes())

    finish(proc);print(target,flush=True)
