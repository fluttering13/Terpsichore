"""Compare Android rendered-frame PTS with ten shared-timeline checkpoints.

Enable `adb shell setprop log.tag.AB_FRAME DEBUG` before opening bug1, play
to the end and replay, then run this script. Disable logging afterwards with
`adb shell setprop log.tag.AB_FRAME INFO`. Media and reports stay under build/.
The metadata callback observes frames submitted to the surface, not screenshots.
"""
import bisect
import json
from pathlib import Path
import re
import statistics
import subprocess


def command(*args):
    return subprocess.check_output(args)


root = Path(__file__).resolve().parents[1] / 'build' / 'ab-frame-mapping'
root.mkdir(parents=True, exist_ok=True)
projects = json.loads(command('adb', 'shell', 'run-as', 'com.example.terpsichore',
                             'cat', 'app_flutter/saved_projects/projects.json'))
project = next(p for p in projects if p['name'] == 'bug1')['data']
tracks = [project['trackA'], project['trackB']]
originals = []
for label, track in zip('AB', tracks):
    media = root / f'{label}.mp4'
    if not media.exists():
        media.write_bytes(command('adb', 'exec-out', 'run-as', 'com.example.terpsichore',
                                  'cat', track['source']['path']))
    probe = json.loads(command('ffprobe', '-v', 'error', '-select_streams', 'v:0',
                              '-show_frames', '-show_entries',
                              'frame=best_effort_timestamp_time', '-of', 'json', str(media)))
    originals.append([round(float(f['best_effort_timestamp_time']) * 1e6)
                      for f in probe['frames']])

pid = command('adb', 'shell', 'pidof', 'com.example.terpsichore').decode().strip()
log = command('adb', 'logcat', '-d', f'--pid={pid}', '-s',
              'AB_NATIVE:I', 'AB_FRAME:D', 'flutter:I').decode('utf-8')
(root / 'logcat.txt').write_text(log, encoding='utf-8')
events = []
frames = {}
for line in log.splitlines():
    match = re.search(r'AB_NATIVE: (\d+) (play|pause|seek \d+) nowNs=(\d+).* pos=(\d+)', line)
    if match:
        identity, action, clock, position = match.groups()
        events.append((int(clock), identity, action, int(position)))
    match = re.search(r'AB_FRAME: frame id=(\d+) ptsUs=(\d+) releaseNs=(\d+)', line)
    if match:
        identity, pts, release = match.groups()
        frames.setdefault(identity, []).append((int(release), int(pts)))

# Shared starts issue A then B. Independent controls are not used in this run.
plays = [e for e in events if e[2] == 'play']
reports = []
for n in range(0, len(plays) - 1, 2):
    pair = plays[n:n + 2]
    if pair[0][1] == pair[1][1]:
        continue
    start_ns = max(p[0] for p in pair)
    stop_ns = min((e[0] for e in events if e[0] > start_ns and e[2] == 'pause'
                   and e[1] in [p[1] for p in pair]), default=start_ns)
    # Only inspect complete replays from the trim starts, not the saved midpoint.
    if any(abs(p[3] - t['trimStartMs']) > 2 for p, t in zip(pair, tracks)):
        continue
    rendered = [sorted(f for f in frames.get(p[1], []) if start_ns <= f[0] <= stop_ns)
                for p in pair]
    if not all(rendered):
        reports.append({'error': 'missing rendered frames', 'pair': pair})
        continue
    duration_us = min((t['trimEndMs'] - t['trimStartMs']) * 1000 / t['rate'] for t in tracks)
    rows = []
    for part in range(10):
        elapsed_us = duration_us * (part + .5) / 10
        # The app's common timeline follows A, not elapsed wall time. Find the
        # actual display of A's corresponding original frame, then inspect B
        # on that same display clock. Missing A frames are failures, not a new
        # clock origin that could hide a freeze.
        a_target = tracks[0]['trimStartMs'] * 1000 + elapsed_us * tracks[0]['rate']
        a_expected = originals[0][max(0, bisect.bisect_right(originals[0], a_target) - 1)]
        # ffprobe and Media3 round rational timestamps in opposite directions
        # (e.g. 6791666 vs 6791667 us); allow only sub-millisecond rounding.
        anchor = next((f for f in rendered[0] if f[1] >= a_expected - 1000), None)
        checkpoint_ns = anchor[0] if anchor else stop_ns + 1
        row = {'part': part + 1, 'shared_ms': round(elapsed_us / 1000, 1)}
        for label, track, source, displayed in zip('AB', tracks, originals, rendered):
            target = track['trimStartMs'] * 1000 + elapsed_us * track['rate']
            expected = max(0, bisect.bisect_right(source, target) - 1)
            index = bisect.bisect_right([f[0] for f in displayed], checkpoint_ns) - 1
            if index < 0 or checkpoint_ns > stop_ns:
                row[label] = {'pass': False, 'reason': 'no frame during checkpoint'}
                continue
            pts = displayed[index][1]
            actual = min(range(len(source)), key=lambda i: abs(source[i] - pts))
            frame_ms = statistics.median([b - a for a, b in zip(source, source[1:])]) / 1000
            row[label] = {'expected_frame': expected, 'actual_frame': actual,
                          'expected_pts_ms': source[expected] / 1000,
                          'actual_pts_ms': pts / 1000,
                          'error_ms': round((pts - target) / 1000, 2),
                          'frame_ms': round(frame_ms, 2),
                          'pass': abs(actual - expected) <= 1 and abs(source[actual] - pts) < 1000}
        rows.append(row)
    reports.append({'run': len(reports) + 1, 'pass': all(r[l]['pass'] for r in rows for l in 'AB'),
                    'rendered_frames': [len(f) for f in rendered], 'rows': rows})

(root / 'mapping.json').write_text(json.dumps(reports, indent=2), encoding='utf-8')
print(json.dumps(reports, indent=2))
if not reports or not all(r.get('pass', False) for r in reports):
    raise SystemExit(1)
