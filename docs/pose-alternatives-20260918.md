# ML Kit and official MoveNet quantized model comparison

Production UI now uses native independent ONNX sessions,1intra-op thread each, A/B Future.wait then median/search. Cancellation fans out to both and waits for cleanup; progress shows each video. Existing multi-person toggle, FPS and pose caches preserved. Non-Android falls back to original ORT bridge.

## Sources and model provenance

- https://developers.google.com/ml-kit/vision/pose-detection/android : bundled base/accurate18.0.0-beta5,33landmarks, STREAM_MODE person tracking and SINGLE_IMAGE_MODE without temporal tracking. CPU selected explicitly for this benchmark; no automatic GPU warm-up mixed into results.
- https://www.tensorflow.org/hub/tutorials/movenet : official Thunder TFLite float16/4 and int8/4 downloads,256input.
- https://developers.google.cn/edge/litert/android : Interpreter runtime1.4.2. Profile-only Maven dependency `com.google.ai.edge.litert:litert:1.4.2`.
- Download URLs: `https://tfhub.dev/google/lite-model/movenet/singlepose/thunder/tflite/float16/4?lite-format=tflite` and corresponding `int8/4`.
- FP16 file12,584,128bytes SHA25641641538679EC79B07D4101E591DDA47D098C09AF29607674B2A40B8A3798DD3.
- INT8 file7,126,768bytes SHA256B72FED22707CD6FB94B5A248B9BDDB9C062B9F445471B4FA263407CF6D222011.

Models retained under build/pose-candidates and device app-private files, not packaged as production assets. Profile-only `PoseAlternativesPlugin` and profileImplementation dependencies; no release ML Kit/LiteRT dependencies. Normal restored APK built before experimental dependencies also avoids shipping these in the user's installed build.

## Protocol

Harness `test/device/thunder_parallel.dart --dart-define=POSE_ALTERNATIVES=true`. Same two manual video pairs. Five backend variants, A/B independent parallel jobs. Two rounds reversing variant order, fixed12FPS for all, median0.5seconds and existing independent-start/speed solver. Fresh sessions/detectors each run; loading/setup included in total and separately instrumented. No video uploads.

ONNX/FP16/INT8 use the same256RGB preprocessing,core gate/grace and rotated retry policy; LiteRT1CPUthread with XNNPACK requested, no GPU delegate. FP16 names weight/model format, not proof of native FP16 CPU arithmetic. Model input dtype checked at runtime(UINT8 or INT32); outputFLOAT32[51]. Timing changes include runtime and model conversion/quantization differences, not just precision.

ML Kit uses full640letterboxed BGR frames converted to Bitmap, CPU-only STREAM_MODE, one detector per video. Its internal detection/tracking replaces our crop/rotation retries, so this is an end-to-end solution comparison, not identical post-detection tracking. Maps33landmarks to COCO17:0,2,5,7,8,11,12,13,14,15,16,23,24,25,26,27,28. Preserve inFrameLikelihood, remove letterbox, then same median/filter/search. Depth and additional16landmarks not fed into solver. Confidence scales are not calibrated across model families. No extra orientation retry for ML Kit in this initial test.

ML Kit SDK is bundled; runtime model-download time is not expected. Asset download/build time excluded. Model/detector construction and first inference warm-up remain included, with second reversed-order round to expose differences. This is two repetitions, not a sustained thermal benchmark.

## Primary experiment results

Raw report `build/pose-alternatives-profile.json`,20rows,complete. ONNX choreo round2 lost foreground (activity visibility logs06:24:26–06:25:02); its38.520s timing is retained in raw evidence but excluded, clean baseline rerun separately. Sampling counts are67 Airflare /148 Choreo across all backends. More calls means direction retries, not more sample frames.

| Backend | Airflare total(mean seconds) | Choreo total(mean seconds) | Native model time/call Airflare / Choreo(ms) | B start/rate Airflare | B start/rate Choreo |
| --- | ---: | ---: | --- | --- | --- |
| ONNX1thread parallel |6.948|11.031|76.0/86.3|.23/.680|1.57/.990|
| Thunder FP16 LiteRT CPU |5.291|8.569|55.8/59.5|.19/.685|1.37/1.045|
| Thunder INT8 LiteRT CPU |3.365|4.630|27.9/24.1|.32/.680|1.60/1.000|
| ML Kit base STREAM parallel |1.977|2.205|16.7/15.4|.24–.31/.680|1.40–1.65/.970–1.025|
| ML Kit accurate STREAM parallel |2.051|2.417|20.8/18.0|.29/.725 or .42/.680|1.39–1.40/1.035–1.040|

Native time includes concurrent CPU contention, plus SDK pipeline work for ML Kit; not isolated per-frame latency on an idle device. Total is pair wall time, not the sum of overlapping model durations. First SDK process initialization included. FP16/INT8 reproduced identical proposals across rounds. Native runtime and model version differ from ONNX; no pure quantization-only causal claim.

Clean foreground ONNX rerun `build/pose-onnx-clean-profile.json`,4rows,complete: Airflare7.009/6.887s, Choreo10.871/11.191s. Device awake and MainActivity top-resumed during checks. Results identical to initial ONNX outputs. Separate rerun timing is not thermally identical to earlier alternative runs. All three reports ended with zero leftover workspaces.

## ML Kit repeatability follow-up

`build/pose-mlkit-check-profile.json`,16rows,complete. STREAM sequential (one video after another) also varied across rounds, so A/B concurrency alone is not established as the cause. Exact SDK state/numerical source remains unisolated.

| ML Kit variant | Airflare seconds | Choreo seconds | Choreo B start/rate |
| --- | ---: | ---: | --- |
| Base STREAM sequential |2.401|3.036|1.45/1.020 or1.47/1.010|
| Accurate STREAM sequential |2.266|3.394|1.61–1.62/.985|
| Base SINGLE_IMAGE parallel |2.727|3.623|1.59/.985 both rounds|
| Accurate SINGLE_IMAGE parallel |2.799|3.981|1.47/1.015 both rounds|

SINGLE_IMAGE reproduced proposals across rounds, but has no native temporal person tracking; do not automatically replace the app's multi-person mode with it. Airflare single-image rates .685/.680 still far from manual .9. STREAM wall-clock/state sensitivity is a hypothesis, not proven implementation detail.

## Visual evidence and recommendation

12 short comparison videos (six alternatives ×two pairs), plus previews, at phone `Download/Terpsichore-Pose-Alternatives`. Left ONNX fixed12FPS baseline; right named alternative. Same manually matched source times and median0.5; these videos do not show automatic proposal playback.

Preview at choreo A1s shows fixed12FPS ONNX skeleton on foreground passer, while INT8 and ML Kit accurate are on intended gray-shirt subject. This is evidence the existing continuity heuristic is not guaranteed identity tracking. Do not generalize from this spot check; different sampling from normal app adaptive setting changes the trajectory. Airflare preview still has limb errors in multiple methods. No whole-video identity annotation performed.

INT8 is the most direct next candidate because it retains the existing crop/retry logic and is substantially faster; its choreo rate matches1.0 but B start1.60 still differs from manual1.2. ML Kit is faster and worth further tracking work, but stream reproducibility and inversion/occlusion need review before promotion. No alternative replaces the user-approved ONNX parallel production backend this turn.

82 Flutter tests pass and analyze clean. Android profile build succeeds. Extra engines/models remain experiments; public release does not gain ML Kit/LiteRT dependencies. Raw output model evidence preserved; no commit/push requested.
