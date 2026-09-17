# RTMPose-S temporal post-processing experiment

## Inputs and scope

Uses the authorized SaveClip download (A) and 20260915_213728_1.mp4 (B).
The raw coordinates are the retained Android inference output from these exact
clips (`files/pose-smoke-result.json`): 16 A frames and 44 B frames. No new model
inference was run for this experiment. Both raw and processed views use identical
predictions, isolating the effect of post-processing.

The app's default source-time window is 0.30 seconds, centered at each timestamp.
AI settings accept finite floating-point values in [0, 1]; 0 bypasses processing.
The preview switch compares raw vs processed without rerunning inference. Settings
persist in pose_settings.json. The skeleton visibility button remains independent.
AI alignment still receives RAW coordinates; this experiment cannot increase its
coverage score by inventing observations.

## Algorithm

- Adjacent time gaps >0.30s, non-increasing times, or large coherent torso jumps
  split processing segments. The torso test is only a conservative discontinuity
  heuristic, not a proof of person identity or a full scene-cut detector.
- Per-joint gaps are filled only between reliable (score >=0.3) endpoints in
  the same segment, separated by <=min(window, 0.25s), with displacement <=0.35
  image heights (aspect-corrected). Leading/trailing and long gaps stay missing.
- Filled scores are half the smaller endpoint score; `inferred` is retained
  through display interpolation and drawn orange. Raw samples are not mutated.
- A centered local-linear x/y fit uses Gaussian time weights and squared
  confidence. One Huber-style residual reweight reduces outlier influence.
  Fewer than 3 supported samples fall back to the original/filled value.
- Fits cannot cross an unfilled joint gap. Confidence is not increased by smoothing.
  No forced bone lengths, rotation search, extrapolation, or model changes.

## Artifacts and initial observations

`build/pose-post/` contains A and B four-column MP4s at original speed and at
half speed. Columns are RAW, 0.15s, 0.30s, 0.50s. Green lines are observed-derived;
orange lines touch a gap-filled joint. Rendered at 30fps for viewing, not inference.
Audio is intentionally omitted. Phone copies are under
`Download/Terpsichore-Pose-Post/`.

| Window | A filled joint samples | B filled joint samples |
| --- | ---: | ---: |
| 0 / 0.15s | 0 | 0 |
| 0.30s | 68 | 42 |
| 0.50s | 68 | 42 |

These are joint samples at inference timestamps, NOT numbers of frames or an
accuracy metric. At 12fps, a 0.15s full window usually contains too few samples
for fitting, so it is effectively raw. At 6fps even 0.30s can be too short.
The gap cap explains why 0.50s fills no additional gaps over 0.30s.

Inspected A at 0.60s and B at 1.50s: short missing limbs become visible at 0.30s,
but interpolated limbs can be off the real person, particularly during inversion.
0.50s changes fast-moving extremities more. Continuity is not proof of accuracy;
watch the videos before choosing a window. Full motion fidelity and alignment
benefit have not been established. Dart desktop per-clip processing was on the
order of milliseconds in this run, but cold/JIT timings are not a phone benchmark.

## Reproduce

```powershell
dart tools/export_pose_post.dart build/pose-smoke-result.json build/pose-post-result.json
python tools/render_pose_post.py build/pose-post-result.json build/pose-user-a.mp4 build/pose-user-b.mp4 build/pose-post
flutter test --no-pub
```

The exporter uses the app's actual Dart algorithm. Python only draws coordinates
and encodes video; it does not implement a competing smoother. Six new core tests
cover bypass, bounded gap filling and provenance, missing edges/long gaps,
irregular-time linear motion, torso discontinuities, and jitter reduction.
