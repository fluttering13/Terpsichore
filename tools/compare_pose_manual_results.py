"""Compare saved proposals with manual linear time mappings; no inference.

Metric: mean absolute B-source-time discrepancy over A's manual playback
duration. This compares proposed start/rate, not player end-of-clip behavior.
Cases receive equal weight; repeated runs are scored before averaging.
"""
import json
import statistics
from pathlib import Path


def phase_error(start_delta, rate_delta, duration):
    """Exact integral of abs(start_delta + rate_delta * t) / duration."""
    if duration <= 0:
        raise ValueError('duration must be positive')
    end_delta = start_delta + rate_delta * duration
    if start_delta * end_delta >= 0:
        return (abs(start_delta) + abs(end_delta)) / 2
    return (start_delta**2 + end_delta**2) / (2 * abs(rate_delta) * duration)


def compare(root):
    manual = {'airflare': (0, .9, 1.3 / .35), 'choreo': (1.2, 1, 5.7)}
    rows = []
    for filename in ['pose-onnx-clean-profile.json',
                     'pose-alternatives-profile.json', 'pose-mlkit-check-profile.json']:
        report = json.loads((root / 'build' / filename).read_text())
        if report['status'] != 'complete':
            raise ValueError(f'Incomplete report: {filename}')
        for run in report['runs']:
            if filename == 'pose-alternatives-profile.json' and run['configuration'] == 'onnx':
                continue
            start, rate, duration = manual[run['case']]
            proposal = run['result']
            rows.append({
                'backend': run['configuration'], 'case': run['case'],
                'repeat': run['repeat'], 'report': filename,
                'b_start': proposal['b_start'], 'b_rate': proposal['b_rate'],
                'start_error_s': abs(proposal['b_start'] - start),
                'rate_error': abs(proposal['b_rate'] - rate),
                'phase_error_s': phase_error(proposal['b_start'] - start,
                                             proposal['b_rate'] - rate, duration),
                'total_s': run['total_us'] / 1e6,
            })
    summary = []
    for backend in sorted({r['backend'] for r in rows}):
        item = {'backend': backend}
        for case in manual:
            selected = [r for r in rows if r['backend'] == backend and r['case'] == case]
            item[case] = {key: statistics.mean(r[key] for r in selected)
                          for key in ['phase_error_s', 'start_error_s', 'rate_error', 'total_s']}
            item[case]['runs'] = len(selected)
        item['equal_case_phase_error_s'] = statistics.mean(item[c]['phase_error_s'] for c in manual)
        summary.append(item)
    summary.sort(key=lambda r: r['equal_case_phase_error_s'])
    return {'metric': 'Unclamped linear B-source-time MAE over manual A playback; equal case weights',
            'summary': summary, 'runs': rows}


if __name__ == '__main__':
    # Constant offset, drift, sign crossing and an exact match.
    assert phase_error(.2, 0, 5) == .2
    assert phase_error(0, .2, 5) == .5
    assert phase_error(-1, 1, 2) == .5
    assert phase_error(0, 0, 5) == 0
    result = compare(Path(__file__).resolve().parents[1])
    print(json.dumps(result, indent=2))
