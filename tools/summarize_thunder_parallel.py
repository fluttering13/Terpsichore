"""Report measured wall times and numeric differences from sequential-2."""
import json
import argparse
import statistics
from pathlib import Path
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument('--report', default='build/thunder-parallel-profile.json')
parser.add_argument('--baseline', default='sequential-2')
args = parser.parse_args()
report = json.loads(Path(args.report).read_text())
print('status:', report['status'], 'completed:', len(report['runs']))
for case in ['airflare', 'choreo']:
    rows = [r for r in report['runs'] if r['case'] == case]
    baseline = next((r for r in rows if r['configuration'] == args.baseline), None)
    if baseline is None:
        continue
    print(case)
    for config in ['sequential-1', 'sequential-2', 'sequential-4', 'parallel-1', 'parallel-2']:
        runs = [r for r in rows if r['configuration'] == config]
        if not runs:
            continue
        times = [r['total_us']/1e6 for r in runs]
        deltas = []
        for r in runs:
            intervals = [t.get('native_intervals', []) for t in r['tracks']]
            if all(intervals):
                overlap = sum(max(0, min(a[1], b[1])-max(a[0], b[0]))
                              for a in intervals[0] for b in intervals[1]) / 1e9
                print('native overlap seconds:', round(overlap, 4),
                      'peak:', max(t['metrics'].get('native_peak_runs', 0) for t in r['tracks']))
            maximum = 0.0
            for ref, current in zip(baseline['tracks'], r['tracks']):
                a = np.array([[f['t'], *np.array(f['points']).ravel()] for f in ref['frames']])
                b = np.array([[f['t'], *np.array(f['points']).ravel()] for f in current['frames']])
                maximum = max(maximum, float(np.max(np.abs(a-b))) if a.shape == b.shape else float('inf'))
            deltas.append(maximum)
        print(config, 'seconds=', [round(t, 3) for t in times],
              'mean=', round(statistics.mean(times), 3), 'max_skeleton_delta=', max(deltas),
              'calls=', [sum(t['metrics']['thunder_calls'] for t in r['tracks']) for r in runs],
              'result=', [r['result'] for r in runs])
