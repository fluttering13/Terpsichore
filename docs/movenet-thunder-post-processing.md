# MoveNet Thunder development and post-processing experiment

2026-09-18. Thunder is now the app's sole runtime pose model. The initially
retained YOLO detector was subsequently removed; see `thunder-only-optimization.md`
for current architecture and fresh mobile results. The migration notes below
record the earlier implementation stages. Other pose
weights have been moved to the Windows Recycle Bin, not permanently destroyed.
Historical scripts, measurements, videos and provenance are retained.

## App migration

- `MoveNetAnalyzer` replaces `RtmPoseAnalyzer`; one-button A/B analysis,
  cancellation, bounded FFmpeg extraction and skeleton visibility are retained.
- Thunder input is **int32 RGB NHWC [1,256,256,3], range 0–255**; output is
  normalized y/x/confidence, 17 COCO points. Confidence is preserved rather
  than truncated in the decoder. Unit tests cover channel order, shape, border
  padding, coordinate restoration, nonfinite outputs and low confidence.
- The shared detector/crop types remain in the historical
  `rtmpose_processing.dart` module. This does not load RTMPose weights.
- Following user approval, mobile inference gained four-orientation recovery.
  The subsequent first optimization reuses the detected ROI and direction,
  refreshes them every 0.5s or on low confidence, and restores adaptive 6/12fps.
  It retains the initial-largest-person / IoU tracker and selects the
  matching orientation by confidence and temporal displacement. This is a mobile
  adaptation, NOT the desktop global appearance tracker / Viterbi selector.
  Detector frames are 640x640 letterboxed; Thunder crops remain 256x256.
- Centered Median is now used by both alignment and overlay, default 0.5s with
  confidence gate 0.15. Existing saved custom windows are preserved. Missing
  joints are not filled and filtering does not cross gaps >0.2s. Raw poses remain
  available by disabling smoothing; changing settings requires rerunning AI to
  obtain a new speed proposal, but does not require repeating cached inference.
- Native Android smoke test successfully loaded Thunder, accepted an int32
  tensor and returned 51 values. The measured 126ms cold call on a zero tensor
  is a compatibility check, **not a real-video mobile speed benchmark**.
- The UI now uses the experimental independent B offset/rate objective: 60
  samples, >=80% A time overlap, >=60% B span, >=50% valid comparison frames,
  pose distance + motion direction + missing-evidence penalty, five coarse/fine
  seeds. B end is retained, A unchanged; unequal playback tails are allowed.
  The legacy full-duration solver remains for regression tests only.
- App previews explicitly warn about cross-person errors and permit rejection
  and undo. Neither these two development examples nor smoothing establish
  general accuracy. Four-direction analysis is slower than one-direction inference.

## Fixed evidence and controls

Same confirmed Airflare and choreography pairs as `expanded-pose-experiment.md`.
No new pose inference is run for the sweep: all variants consume the same
Thunder selected raw predictions. Airflare uses the prior rot4 pass;
choreography uses the prior raw pass. All clips stayed local.

This isolates post-processing changes. It cannot repair the known choreography
cross-person predictions: smoothing the wrong subject is still the wrong subject.
All choreography numeric results below are contaminated, exploratory proposals,
not validated matches to the intended dancer.

36 configurations, each evaluated on both pairs:

- Confidence gates 0.30, 0.20, 0.15.
- Raw; confidence-weighted Gaussian 0.3/0.5s; local-linear 0.3/0.5s;
  robust local-linear 0.3/0.5s; median 0.3/0.5s; One Euro.
- At each threshold, robust 0.3s with box/isolated-spike rejection, with and
  without bounded one-frame gap filling (at most 0.2s between observations).
- Windows are **full widths in source seconds**, not frame counts or playback
  seconds. Centered filters are offline/acausal. Filtering does not cross an
  unfilled missing run or a time gap above 0.2s. One Euro resets on longer gaps.
- Gap points carry `inferred` flags and half the weaker endpoint confidence;
  eligible synthetic points can contribute to this experimental search and are
  counted in the report. Orange preview edges indicate inferred points. This is
  not an endorsement of inferred joints as reliable alignment evidence.
- To exercise lower thresholds with the existing fixed-0.3 matcher, accepted
  scores below 0.3 are floored to 0.3; rejected scores become zero. This is an
  explicit confidence-policy ablation, not calibrated model probabilities.
- Same search and pose/motion loss for every variant. No manual reference rate
  enters inference, filtering or the optimizer. References are used only to
  evaluate and rank completed predictions.

Ranking is the sum of each case's mean absolute B-source mapping error divided
by selected B length. A rejected case contributes 1. This deliberately penalizes
failure, but it can prefer an invalid cross-person numerical answer over a safe
rejection. Therefore it is a **development-set numerical ranking only**, not an
automatic production selection rule. These two examples are not held-out tests.

## Results

Entries show B start / B speed; A and B end bounds remain unchanged.

| Variant | Airflare | Mean mapping error | Choreography | Mean mapping error |
| --- | --- | ---: | --- | ---: |
| Manual | 0s / 0.900x | — | 1.2s / 1.000x | — |
| Raw, gate 0.30 | 0.07s / 0.830x | 0.0788s | rejected | — |
| Raw, gate 0.15 | 0.17s / 0.750x | 0.1604s | 1.51s / 1.010x | 0.3385s |
| Median 0.5s, gate 0.15 | 0.26s / 0.715x | 0.1819s | 1.51s / 0.990x | 0.2815s |
| Gaussian 0.3s, gate 0.20 | 0.21s / 0.740x | see JSON | 1.57s / 0.995x | see JSON |
| One Euro, gate 0.20 | 0.18s / 0.750x | 0.1567s | 1.58s / 0.990x | 0.3515s |

The numerical winner is **median 0.5s / confidence 0.15**, development score
0.09023 versus raw gate-0.15's 0.09461. Filtering both A and B sequences took
about 22ms for Airflare and 48ms for choreography on desktop CPU (post-processing
only, not inference, video decode or search). It is **not a universal winner**:

- Airflare is worse than both raw gate-0.15 and the original raw gate-0.30 run.
  Fast-motion smoothing does not improve this example's manual correspondence.
- Choreography gains a numeric match by accepting weaker evidence, but known
  cross-person contamination remains and B start is still +0.31s from manual.
- No tested configuration reliably reproduces both manual references.

Initial decision was to keep the numerical winner offline. The user subsequently
approved integrating it into the app; Median is now the default for new settings.
The identity/overlap limitations above still apply. All sweep variants remain
reproducible experiments; mobile tracking and rotated input preparation differ,
so the table above must not be presented as newly measured mobile results.

## Artifacts and reproduction

- `build/thunder-post/report.json`: all 36 configurations / 72 case results.
- `ranking.json`: development-only numeric order, warnings above apply.
- Four `*-post-comparison.mp4`: raw / numeric winner / Gaussian / robust+gap /
  One Euro, half-speed, 24fps display of 12fps pose evidence.
- Two `*-manual-vs-post.mp4`: manual and predicted timing, five labelled
  sections; choreography has an explicit identity-contamination warning.
- Phone delivery: `Download/Terpsichore-Thunder-Post`.
- Cleanup audit: `build/retired-pose-weights.json`, 15 exact model files moved
  to Recycle Bin. No user video, app data or previous experiment result removed.

```powershell
python tools/download_movenet.py
build/manual-pose-env/Scripts/python.exe tools/benchmark_thunder_post.py
build/manual-pose-env/Scripts/python.exe tools/test_thunder_post.py
build/manual-pose-env/Scripts/python.exe tools/render_thunder_post.py
flutter test
flutter analyze
```

The sweep requires the retained Thunder raw caches under `build/pose-expanded`.
If those caches are absent, recreate only Thunder's raw/rot4 passes using
`benchmark_expanded_pose.py --models movenet-thunder`; the archived all-model
benchmarks need their historical weights downloaded again to be rerun.
