"""Create four-window comparison videos from Dart post-processed coordinates.
No inference or alternative smoothing is performed here. Orange = gap-filled.
python tools/render_pose_post.py results.json A.mp4 B.mp4 output-directory
"""
import json
import pathlib
import subprocess
import sys
import cv2
import numpy as np

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
out = pathlib.Path(sys.argv[4])
out.mkdir(parents=True, exist_ok=True)
bones = [(5,6),(5,7),(7,9),(6,8),(8,10),(5,11),(6,12),(11,12),(11,13),(13,15),(12,14),(14,16),(0,1),(0,2),(1,3),(2,4)]
for clip, path in zip(['a', 'b'], sys.argv[2:4]):
    capture = cv2.VideoCapture(path)
    target = out / f'{clip}-pose-post-comparison.mp4'
    encoder = subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','bgr24','-s','1440x700','-r','30','-i','-','-an','-c:v','libx264','-crf','18','-pix_fmt','yuv420p',str(target)], stdin=subprocess.PIPE)
    try:
        for i, frame in enumerate(data[clip]['0.0']['frames']):
            capture.set(cv2.CAP_PROP_POS_MSEC, frame['t'] * 1000)
            ok, source = capture.read()
            if not ok:
                raise RuntimeError(f'Cannot decode {clip} at {frame["t"]}')
            tiles = []
            for window in ['0.0','0.15','0.3','0.5']:
                tile = np.zeros((700,360,3),dtype=np.uint8)
                tile[45:685] = cv2.resize(source,(360,640))
                label = 'RAW' if window == '0.0' else f'SMOOTH {window}s'
                cv2.putText(tile,label,(10,27),cv2.FONT_HERSHEY_SIMPLEX,.62,(255,255,255),1,cv2.LINE_AA)
                points = data[clip][window]['frames'][i]['points']
                if points:
                    def pos(j): return (round(points[j][0]*360),45+round(points[j][1]*640))
                    for a,b in bones:
                        if min(points[a][2],points[b][2]) < .15: continue
                        color = (0,165,255) if points[a][3] or points[b][3] else (100,255,100)
                        cv2.line(tile,pos(a),pos(b),(0,0,0),4,cv2.LINE_AA)
                        cv2.line(tile,pos(a),pos(b),color,2,cv2.LINE_AA)
                    for j,p in enumerate(points):
                        if p[2] >= .15: cv2.circle(tile,pos(j),3,(0,165,255) if p[3] else (0,255,255),-1)
                tiles.append(tile)
            encoder.stdin.write(np.hstack(tiles).tobytes())
    finally:
        capture.release()
        encoder.stdin.close()
    if encoder.wait() != 0: raise RuntimeError('Encoding failed')
    # A separate slow viewing version is labelled by filename; source-time windows unchanged.
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(target),'-vf','setpts=2*PTS','-an',str(out/f'{clip}-pose-post-comparison-half-speed.mp4')],check=True)
    print(target)
