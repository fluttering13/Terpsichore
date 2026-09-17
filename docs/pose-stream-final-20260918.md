# Final pose backends and no-retry comparison

This document supersedes earlier ONNX/FP16/retry experiment recommendations.

## Shipped policy

UI update: the multi-person switch has been removed. Production A/B always
enables tracking on both platforms; legacy false preferences are ignored and
the retired key is omitted when saving settings. Independent-image modes remain
internal benchmark options only. FPS, median and skeleton visibility remain.

- Android: bundled ML Kit Accurate, one detector per A/B video, STREAM when
  tracking is enabled, SINGLE_IMAGE when disabled. A/B run concurrently.
- Other native platforms: official Thunder INT8 v4, one interpreter per video,
  one inference thread each. Inference is dispatched off the UI isolate.
- INT8 stream-like tracking reuses the previous pose ROI. Missing/low-confidence
  torso, large core displacement or time gaps reset the NEXT sample to full-frame.
  Preserve raw landmark confidence; do not erase the whole pose when tracking fails.
- Both paths perform exactly one model call per selected sample. No same-frame
  rotation retries or later repair inference. Tracking off uses full-frame INT8.
- Both share configurable FPS, 0.5-second default median, existing 17-point
  overlay, fixed-A/B-start-and-speed search and speed ceiling 4x.

ML Kit's public STREAM contract is available at
https://developers.google.com/ml-kit/vision/pose-detection/android . Its private
tracking implementation is not published; INT8 follows the same broad pattern,
not identical SDK internals or guaranteed person identity. It has no separate
person detector: reacquisition uses full-frame SinglePose inference.

## Same fixture measurement

Samsung SM-S9180, foreground, 12 FPS, median 0.5 seconds, two repetitions of each
sequential/parallel configuration in reversed order. Native INT8 Dart/FFI path
was forced on Android to validate the common code, NOT measured on iOS.
`build/int8-stream-final.json` and `build/mlkit-final-result.json` each contain
8 completed runs and zero leftover workspaces. Harness asserts model calls equal
sampled frames (67 total Airflare, 148 Choreo). Failed strict-gating experiment
is retained separately in `build/int8-stream-result.json` and not used below.

Parallel results (time is whole pair pipeline, not just inference):

| Backend | Case | Mean seconds | B start / rate, round 1; round 2 | Manual-map MAE |
| --- | --- | ---: | --- | ---: |
| Accurate STREAM | Airflare | 1.994 | 0.42 / 0.690; 0.40 / 0.680 | 0.200 s |
| INT8 stream-like | Airflare | 4.256 | 0.16 / 0.800 both | 0.095 s |
| Accurate STREAM | Choreo | 2.410 | 1.53 / 0.995; 1.60 / 1.000 | 0.358 s |
| INT8 stream-like | Choreo | 6.823 | 1.52 / 0.985 both | 0.277 s |

Manual Airflare: A 0–1.3 at 0.35x, B 0–4.2 at 0.9x.
Manual Choreo: A 0–5.7 at 1x, B 1.2–7.2 at 1x.
MAE integrates the absolute difference between predicted and manual
`B_start + B_rate * elapsed_A_playback` over the entire A playback duration.
It uses B-source seconds without clipping at trim end. Score each run before
averaging. It measures start/rate closeness, not skeleton accuracy.

INT8 is closer to the manual maps on these examples, but its valid comparison
coverage is only about 63% / 72%, and both proposals are ambiguous. Accurate is
faster, with approximately 90–97% / 88–92% coverage, but varies between runs.
No claim that the backends now produce equivalent skeletons or generally equal
quality. The 0.8x Airflare result still differs from manual 0.9x. No per-video
hardcoded adjustment or tuning to the expected start/rate was added.

## Regression coverage and platform limits

- 99 Flutter tests, including 17 new platform-policy, parallel scheduling/drain,
  independent state, ROI loss/reacquisition/time-gap and recorded-pose regressions.
- `test/fixtures/pose_stream_reference.json` contains pose coordinates only, no
  source videos. Four regression tests exercise median + alignment using recorded
  native outputs; these do NOT validate live inference on future SDKs/devices.
- Android reminder JUnit tests pass; analyze and formatting checks pass.
- Profile Android app built; current normal UI restored after benchmarking.
- iOS build and real iOS performance remain unverified (Windows host, no Xcode).
  Official `tflite_flutter` supports native platforms; desktop runtimes require
  platform packaging, and this repo has no desktop runners. Web is not supported
  by this FFI path. Do not advertise all non-Android platforms as tested.
- Remaining desirable device tests: occlusion/identity-labelled videos, long clips,
  memory/thermal profiling, iOS install/inference and cancel-during-inference stress.

## Cleanup

Removed 65 old local test MP4s, 4 old APKs and 4 retired weight files (1,473,495,516
bytes total). Details remain in local `build/pose-cleanup-manifest.json`. Original
phone videos, JSON evidence, current APK and INT8 asset remain. Removed old ONNX
pose/alternative native plugins and retired device harnesses. Historical research
scripts/docs remain for provenance, but their deleted models/videos must be
downloaded/regenerated to replay old experiments. ONNX runtime dependency stays
because the unrelated music stem separator uses it. Build artifacts are ignored
and not pushed; no new source videos are included in the commit.
