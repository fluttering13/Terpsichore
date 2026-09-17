# A/B scheduling and model intra-op thread benchmark

Harness `test/device/thunder_parallel.dart`. Configurations: sequential A/B with 2 or 4 model intra-op threads; concurrent A/B jobs with independent sessions using 1 or 2 threads each. Inter-op stays1. Current production core-gate/grace tracking enabled; early-exit and temporal repair off. Adaptive FPS, same manual fixtures and median0.5. Normal app scheduling/default remains sequential/2 pending user decision.

Two runs per configuration and pair; second round reverses configuration order to partially counter ordering/thermal effects. No warm-up exclusion; each run includes fresh sessions and workers. Concurrent wall time is measured around Future.wait, NOT the sum of overlapping per-track times. Each analyzer owns decoder sessions/workspace/worker/model. A failure cancels both analyzers and Future.wait waits for both to settle before reporting failure. Final check asserts zero leftover workspaces.

## Important native limitation

Installed `flutter_onnxruntime`1.8.5 Android implementation creates one `makeBackgroundTaskQueue()` MethodChannel, and wraps its entire `onMethodCall` in `synchronized(lock)` (FlutterOnnxruntimePlugin.kt around lines191,207). The `session.run` call is inside that handler. Therefore independently scheduled A/B jobs can overlap decoding/crop preparation, but their native model calls are serialized by the plugin. Even two sessions do not give two simultaneous model runs with this bridge. Concurrent call timing can include queue wait.

No global pub-cache edits or plugin concurrency patches were made. Real simultaneous model execution would need a reviewed native bridge change (separate execution tasks and safe session/tensor lifecycle management), not simply more Dart Futures or isolates.

Reports: `build/thunder-parallel-profile.json`; summarize with `tools/summarize_thunder_parallel.py`. Both full skeleton arrays and alignment results retained for numerical equivalence checks. This harness does not benchmark UI interaction or parallel cancellation on-device.

## Completed SM-S9180 Profile results

16 runs complete, zero leftover workspaces. Phone awake at start/intermediate/end checks. Battery temperature observed31.8→33.0→34.3°C (not CPU temperature); second-round times generally higher. Only two repetitions, so small speedups are provisional and not a thermal-controlled benchmark.

| Scheduling / intra-op threads per model | Airflare runs (s) | Mean | Choreo runs (s) | Mean |
| --- | --- | ---: | --- | ---: |
| Sequential /2 | 7.151,7.772 | 7.461 | 13.849,15.790 | 14.819 |
| Sequential /4 | 6.094,6.447 | 6.270 | 12.521,13.017 | 12.769 |
| Concurrent jobs /1 | 7.019,7.649 | 7.334 | 15.628,18.138 | 16.883 |
| Concurrent jobs /2 | 6.763,7.269 | 7.016 | 13.372,14.915 | 14.144 |

Concurrent jobs/2 save approximately6.0% Airflare,4.6% Choreo vs sequential/2. Every sampled timestamp, normalized keypoint coordinate and confidence score matches sequential/2 exactly across both runs. Calls91/201 and proposals Airflare0.22/0.73, Choreo1.51/1.02 unchanged. This is pipeline overlap, NOT simultaneous session.run execution.

Sequential/4 is fastest but output is not equivalent: Airflare85 calls and different sample count, B0.20/0.68; Choreo201 calls with changed skeleton values, B1.58/0.955. Concurrent jobs/1:83/205 calls, B0.22/0.685 and1.56/0.985. Each configuration reproduced its own results across rounds. Thread-count-dependent numerical/kernel differences plus downstream crop/threshold feedback are a possible explanation, not yet isolated by a fixed-input tensor comparison. Do not claim identical quality or isolated inference acceleration from these differing trajectories.

Normal app remains sequential/2. No UI parallel scheduling promoted.82 Flutter tests passed, analyze clean; thread count rejects values outside1–4 before native allocation. Fresh normal Profile build restored after benchmark.
