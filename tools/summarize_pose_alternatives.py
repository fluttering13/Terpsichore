"""Summarize native alternatives and emit renderer-compatible reports."""
import json
import argparse
import statistics
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--report', default='build/pose-alternatives-profile.json')
args = parser.parse_args()
report = json.loads(Path(args.report).read_text())
print('status', report['status'], 'rows', len(report['runs']))
if report['status'] == 'failed':
    print(report.get('error'), report.get('stack'))
for backend in dict.fromkeys(r['configuration'] for r in report['runs']):
    cases = []
    for case in ['airflare', 'choreo']:
        rows = [r for r in report['runs'] if r['configuration'] == backend and r['case'] == case]
        if not rows:
            continue
        # Preserved raw report: this exact run lost foreground (device log).
        # Keep its skeleton evidence but exclude its contaminated timing.
        if Path(args.report).name == 'pose-alternatives-profile.json' and backend == 'onnx' and case == 'choreo':
            rows = [r for r in rows if r['repeat'] != 1]
            print('Excluded ONNX choreo repeat1 timing: app backgrounded; see clean rerun report.')
        print(backend, case, 'times', [round(r['total_us']/1e6, 3) for r in rows],
              'mean', round(statistics.mean(r['total_us']/1e6 for r in rows), 3),
              'native_mean_ms', [round(sum(t['metrics'].get('native_compute_us', 0) for t in r['tracks']) /
                                      sum(t['metrics']['thunder_calls'] for t in r['tracks'])/1000, 2) for r in rows],
              'calls', [sum(t['metrics']['thunder_calls'] for t in r['tracks']) for r in rows],
              'results', [r['result'] for r in rows])
        cases.append(rows[-1])
    if len(cases) == 2:
        Path(f'build/pose-alternative-{backend}.json').write_text(json.dumps({'status': 'complete', 'cases': cases}))
