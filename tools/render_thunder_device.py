"""Compare fresh phone skeletons against retained desktop evidence at equal times."""
import json
import argparse
import math
from pathlib import Path
import cv2
import numpy as np
from benchmark_manual_alignment import CASES
from benchmark_thunder_post import process
from render_expanded_pose import VideoCache, read, tile, writer, finish

parser = argparse.ArgumentParser()
parser.add_argument('--report', default='build/thunder-pairs-device.json')
parser.add_argument('--out', default='build/thunder-device')
parser.add_argument('--reference-phone', help='Compare against another native report instead of desktop')
parser.add_argument('--left-label', default='RETRY')
parser.add_argument('--right-label', default='NO RETRY')
args = parser.parse_args()
root = Path(args.out)
root.mkdir(parents=True, exist_ok=True)
report = json.loads(Path(args.report).read_text())
assert report['status'] == 'complete', report['status']
ranking = json.loads(Path('build/thunder-post/ranking.json').read_text())
reference = json.loads(Path(args.reference_phone).read_text()) if args.reference_phone else None
cv2.setNumThreads(1)
for case, native in zip(CASES, report['cases']):
    assert case['name'] == native['case']
    desktop = json.loads(Path(f'build/thunder-post/{case["name"]}-{ranking[0]["id"]}-selected.json').read_text())
    caches = {s: VideoCache(case[s]) for s in ['a', 'b']}
    def selection(tracks):
        output = {}
        for track in tracks:
            side = track['side']
            _, w, h = caches[side].frames[0]
            ts = np.array([f['t'] for f in track['frames']])
            points = np.array([f['points'] for f in track['frames']])
            points[:, :, 0] *= w
            points[:, :, 1] *= h
            smoothed, _ = process(ts, points, [None]*len(ts), 'median', .5, .15)
            output[side] = [dict(t=float(t), person=dict(points=p.tolist())) for t, p in zip(ts, smoothed)]
        return output
    mobile = selection(native['tracks'])
    if reference:
        desktop = selection(next(c for c in reference['cases'] if c['case'] == case['name'])['tracks'])
    comparison = 'comparison' if reference else 'desktop-vs-phone'
    left, right = (args.left_label, args.right_label) if reference else ('DESKTOP', 'PHONE')
    target = root / f'{case["name"]}-{comparison}.mp4'
    proc = writer(target, 1280, 560)
    for i in range(math.ceil(case['a_end']/case['a_rate']*24)):
        elapsed = i/24
        panels = []
        for side, data, name in [('a', desktop, f'{left} A'), ('a', mobile, f'{right} A'),
                                  ('b', desktop, f'{left} B'), ('b', mobile, f'{right} B')]:
            t = elapsed*case['a_rate'] if side == 'a' else case['b_start']+elapsed*case['reference_b_rate']
            panels.append(tile(read(caches[side], t, case[side+'_end']), data[side], t,
                               name, 'Same source times / median 0.5s', threshold=.15,
                               processing_label=comparison))
        combined = np.hstack(panels)
        if i == 24:
            cv2.imwrite(str(target.with_suffix('.jpg')), combined)
        proc.stdin.write(combined.tobytes())
    finish(proc)
    print(target, flush=True)
