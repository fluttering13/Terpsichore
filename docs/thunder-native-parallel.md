# Independent native Thunder sessions, one thread per video

Update: user subsequently approved production integration. Normal A+B Android UI now creates independent native sessions with one intra-op thread each, joins both jobs before alignment, and cancels both on cancel/dispose/failure. See `pose-alternatives-20260918.md`. Earlier experiment/default descriptions below are historical.

Experimental app-owned Android `ThunderInferencePlugin` uses ONNX Runtime Android1.23.0, the same version as flutter_onnxruntime1.8.5. No pub-cache modifications. App adds explicit ORT dependency for compile-time access; Gradle resolves the same artifact.

Two executor workers, distinct sessions, each intra-op1/inter-op1. Per-session monitor serializes same-session run/close. Engine lifetime read lock permits independent runs; detach takes write lock, waits for running operations and closes sessions. Tensors and output Results live only inside one run and are closed with `use`. Process-shared OrtEnvironment is not closed by this bridge. Queued calls check detach state. Model CPU run intervals are recorded with System.nanoTime; outputs carry51 keypoint numbers, not externally owned tensor handles.

Production analyzer selects this only with `nativeParallelBackend:true`; normal UI remains original backend, sequential2threads. This change is a benchmark, not promoted UI scheduling. Third-party plugin and custom bridge coexist; engine-detach ordering with third-party environment teardown has not been stress-tested, so further lifecycle review is needed before promotion.

Harness `test/device/thunder_parallel.dart` currently benchmarks sequential1 and parallel1 with the new backend, two rounds in reversed order. A/B raw sequences are aggregated after both jobs finish; then same median0.5 and solver run. All current core-gate/grace tracking enabled. No change to FPS, image preprocessing, rotation candidate selection or solver thresholds.

## Results

`build/thunder-native-parallel-profile.json`,8rows,complete,zero leftover workspaces. Two repetitions only; phone awake at start and after benchmark (safety-test start). Timing includes setup,decode,crop,inference,filter/search, not user taps/rendering/export.

| Pair | Sequential1 runs | Mean | Parallel1 runs | Mean | Reduction |
| --- | --- | ---: | --- | ---: | ---: |
| Airflare | 7.174,7.650s | 7.412s | 6.050,6.055s | 6.052s | 18.3% |
| Choreo | 15.882,17.040s | 16.461s | 11.106,10.826s | 10.966s | 33.4% |

All timestamps,coordinates,confidence values match sequential1 exactly in both rounds. Calls83/205. Airflare B0.22/0.685, Choreo B1.56/0.985. These match earlier one-thread plugin proposals, but **not** the current app's two-thread outputs (0.22/0.73 and1.51/1.02). Parallelization itself preserved the one-thread result; this is not evidence of equivalence to the current app default.

Native run intervals overlap1.692/1.548s for Airflare and7.268/7.831s for Choreo. Sequential runs overlap0. The process-wide peak counter reaches2 and remains2 in subsequent sequential runs; interval overlap, not the cumulative peak, is the proof of concurrent calls.

Compared with prior app-default sequential2 mean7.461/14.819s, observed new totals6.052/10.966s are lower, but those are different runs/threads/output trajectories. Do not call it a controlled quality-equivalent comparison. Memory peak and thermally sustained performance have not been measured.

82 Flutter tests pass; safety harness `test/device/thunder_native_safety.dart` exercises malformed tensor, concurrent run/close, repeated close, rejection after close, and cancelling both analyzers with workspace cleanup.

`build/thunder-native-safety.json` completed: invalid_tensor=true, concurrent_close=completed, closed_session_rejected=true, cancel_both=true, leftover_workspaces=0. Analyze clean. Restored normal Profile app with experimental backend disabled after tests.
