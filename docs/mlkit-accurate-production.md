# ML Kit Accurate Android default (2026-09-18)

User selected Accurate after the model comparison. Android A+B now uses one
Accurate detector per video, CPU preference, concurrent A/B analysis followed by
the existing median smoothing and alignment search. Non-Android retains ONNX.
SDK internal inference thread count is not controlled by the app.

`AccuratePosePlugin` is registered directly in all Android build variants, on a
dedicated channel; only Accurate's bundled dependency was promoted from profile
to implementation. Other experimental engines remain profile-only. Existing ONNX
code/assets are retained for fallback/comparison, not deleted.

Multi-person filtering on selects STREAM_MODE; off selects SINGLE_IMAGE_MODE.
Neither Android path uses Thunder crop/core/rotation retries. The UI explains
tracking limitations. FPS, smoothing, skeleton visibility, B search margin and
4x speed ceiling remain unchanged. 33 SDK landmarks are mapped to the existing
17-point overlay/search representation to preserve the benchmark pipeline.
STREAM tracks a prominent person, not a guaranteed user-selected identity.
Official mode documentation: https://developers.google.com/ml-kit/vision/pose-detection/android

## Production-channel sequential versus parallel measurement

Samsung SM-S9180, fixed 12 FPS, median 0.5 seconds, same two manual fixtures.
Harness `test/device/thunder_parallel.dart` with `POSE_ACCURATE_PARALLEL=true`.
Two repeats in reversed configuration order, app foreground/device awake.
Evidence `build/mlkit-production-parallel.json`: complete, 8 runs, 0 leftover
workspaces. This tests the production native plugin through the benchmark UI.

| Case | Sequential runs (s) | Parallel runs (s) | Mean reduction |
| --- | --- | --- | --- |
| Airflare | 2.481, 2.170 | 1.904, 2.005 | 16% (2.326 to 1.955) |
| Choreo | 2.966, 3.064 | 2.346, 2.346 | 22% (3.015 to 2.346) |

Whole-pair wall times include setup, decoding, transfers, detection, smoothing
and alignment, not isolated inference latency. Recorded overlapping native SDK
call intervals: Airflare 0.103/0.048 seconds, Choreo 0.898/0.826 seconds;
sequential overlap is zero. SDK-call overlap does not prove its internal kernels
all execute simultaneously. Different video lengths and non-inference work
prevent a guaranteed 2x speedup.

Parallel proposals varied: Airflare B start/rate 0.25/0.735 and 0.35/0.715;
Choreo 1.37/1.025 and 1.59/1.000. Sequential proposals also vary; this remains
an SDK/pipeline repeatability limitation, not an established parallelism bug.
Airflare still does not reproduce manual B rate 0.9. Median plus search consumed
86–95 ms Airflare and about 150 ms Choreo in parallel runs.

Verification: Flutter analyze clean; existing 82 Flutter tests passed; normal
profile APK and foreground benchmark APK built. Normal UI APK reinstalled with
data-preserving update after the benchmark. Full manual UI gesture regression
and release APK build were not performed in this pass.
