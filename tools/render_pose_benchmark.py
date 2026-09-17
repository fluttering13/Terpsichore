"""Render all measured frames; columns=models, top=baseline, bottom=post.

python tools/render_pose_benchmark.py A.mp4 B.mp4
Only uses existing predictions; does not rerun or interpolate inference.
"""
import json
import subprocess
import sys
import cv2
import numpy as np
from benchmark_pose_candidates import OUT, NAMES, tile

report=json.loads((OUT/'report.json').read_text(encoding='utf-8'))
for clip,path in zip(['A','B'],sys.argv[1:3]):
    rows=[r for r in report['frames'] if r['clip']==clip]
    times=sorted(set(r['t'] for r in rows))
    capture=cv2.VideoCapture(path)
    target=OUT/f'{clip}-comparison.mp4'
    process=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','bgr24','-s','1080x960','-r','6','-i','-','-an','-c:v','libx264','-pix_fmt','yuv420p',str(target)],stdin=subprocess.PIPE)
    for t in times:
        capture.set(cv2.CAP_PROP_POS_MSEC,t*1000)
        ok,image=capture.read()
        if not ok: raise RuntimeError(f'Cannot decode {clip} at {t}')
        strips=[]
        for post in [False,True]:
            tiles=[]
            for name in NAMES:
                row=next(r for r in rows if r['t']==t and r['model']==name and r['post']==post)
                person=None if row['points'] is None else (None,np.array(row['points']))
                tiles.append(tile(image,person,f'{name} {"post" if post else "raw"} {t:.2f}s'))
            strips.append(np.hstack(tiles))
        process.stdin.write(np.vstack(strips).tobytes())
    process.stdin.close()
    if process.wait()!=0: raise RuntimeError('Video encoder failed')
    capture.release()
    print(target)
