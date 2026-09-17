"""Visual spot checks at chosen source times, without new inference."""
import json
from pathlib import Path
import cv2
import numpy as np
from render_expanded_pose import VideoCache,read,tile
from diverse_pose_adapters import NAMES

root=Path('build/pose-expanded')
report=json.loads((root/'report.json').read_text())
case=next(c for c in report['cases'] if c['name']=='choreo')
for side in ['a','b']:
    cache=VideoCache(case[side])
    selections={n:json.loads((root/f'choreo-{n}-raw-selected.json').read_text())[side] for n in NAMES}
    for t in [1.5,3.,5.]:
        frame=read(cache,t,case[side+'_end'])
        tiles=[tile(frame,selections[n],t,n,'Subject tracking check') for n in NAMES]
        cv2.imwrite(str(root/f'choreo-{side}-{t:.1f}s-tracking.jpg'),np.hstack(tiles))
