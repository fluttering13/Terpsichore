# Thunder first mobile optimization — 2026-09-18

Same four authorized video fixtures, SM-S9180 CPU, 2 intra-op / 1 inter-op
threads. Thunder weights, 256-square input, Median 0.5s / gate 0.15 and
alignment objective are unchanged. No TFLite/GPU migration was made this round.

## Implementation

- Reuse detected ROI between 0.5-source-second checks; low confidence triggers
  reacquisition earlier. Initial acquisition still checks all four orientations.
  Subsequent detector refresh starts with the current direction, falling back
  to others when the previous subject cannot be matched by IoU.
- Thunder first tries the previous direction, searching all directions on low
  confidence and every 0.5 source seconds. Direction changes remain possible
  during inverted/rotating movement, rather than assuming the whole clip upright.
- Restore existing adaptive 6/12fps sampling: short clips <=4s, uncertain
  observations and fast motion use dense sampling.
- Direct rotated-ROI sampling avoids full-image rotations for pose calls.
  Eight tensor comparisons (four directions, two ROIs including border padding)
  verify byte-for-byte equality to the old crop for an identical ROI.
- Fuse detector rotation/preparation into one background compute call.
- Add detector/Thunder call counts and input/run/output microsecond counters.
  `*_run_us` includes the session invocation boundary, not isolated silicon time.
- Legacy exhaustive path remains accessible with `MoveNetAnalyzer(optimized:
  false)` for regression/benchmarking, not selected by the app UI.

## Same-build-mode results

Single fresh runs, not repeated thermal-controlled benchmarks. Totals include
both videos and post/search; do not compare directly with single-call Google
latency numbers. Baseline and optimized columns below both use Debug.

| Case | Baseline time | Optimized time | Speedup | Baseline B start / speed | Optimized B start / speed |
| --- | --- | --- | --- | --- | --- |
| Airflare | 155.043s | 29.698s | 5.22x | 0.35s / 0.710x | 0.31s / 0.710x |
| Choreography | 406.659s | 65.582s | 6.20x | 1.50s / 1.005x | 1.48s / 1.015x |

Airflare comparison-frame coverage stays 96.7%; choreography falls from 91.7%
to 85%. Choreography remains ambiguous. This is NOT a no-quality-loss claim:
ROI reuse and adaptive sampling change evidence. Joint position differences are
visible in the exported spot-check; known subject-crossing limitations remain.
The manual reference for Airflare remains 0s / 0.9x, so it is still not matched.

Measured Debug Thunder invocation averages: 54.3–61.0ms across the four tracks.
Detector averages: 358.4–374.7ms. The remaining detector and data-path overhead
are substantial; do not describe this app pipeline as realtime.

Profile/AOT verification completed: Airflare 29.355s and choreography 65.715s,
with identical proposed offsets/rates to optimized Debug. Thus the measured
5–6x improvement is primarily workflow reduction, not a Debug/Profile artifact.

Profile choreography processes 145 sampled frames but invokes Thunder 311 times
and YOLO 59 times. Thunder invocation time totals 18.104s (58.2ms/call), detector
invocation time 22.497s (381.3ms/call), measured tensor input/output 6.774s,
post/search 0.154s. The remaining 18.186s includes session setup/close, decoding,
rotation/crop preparation, isolate work/transfers, NMS and cleanup; these were
not individually instrumented, so no attribution within this remainder is made.
Overall throughput is only about 2.2 sampled frames/s despite Thunder's invocation
rate equivalent to about 17 calls/s. Calls/s is NOT the pipeline's frames/s.

Normal Debug app was restored after native testing. Updated evidence previews
are delivered separately under `Download/Terpsichore-Thunder-Optimized`.

## Google reference and next boundary

[Google's 2021 TFLite benchmark](https://blog.tensorflow.org/2021/08/pose-estimation-and-classification-on-edge-devices-with-MoveNet-and-TensorFlow-Lite.html)
reports Thunder FP16 on Pixel 5 at 155ms CPU / 45ms GPU, using its sample app
under sustained load. It also describes reuse of the previous pose's crop.
Those results are device/runtime specific and do not include our extra YOLO
multi-person / orientation search workflow. Current implementation still uses
ONNX CPU and detector boxes, not Google's exact pose-derived cropping algorithm.

Further work should isolate ROI/identity quality before reducing reacquisition,
and compare a detector-only output path / native data transport and official
TFLite FP16 acceleration with the same inputs. GPU latency is not guaranteed.

## Reproduction and artifacts

- `test/device/thunder_pairs.dart`: production native pipeline, no pose cache;
  `--dart-define=POSE_OPTIMIZED=false` selects exhaustive baseline.
- `build/thunder-pairs-baseline-debug.json`: prior full native result preserved.
- `build/thunder-pairs-optimized-debug.json`: new raw poses, timings, counters.
- `build/thunder-pairs-optimized-profile.json`: separate AOT/Profile run.
- `tools/render_thunder_device.py --report <json> --out <directory>` produces
  same-source-time desktop/phone skeleton comparisons (not proposed-rate playback).
- 70 Flutter tests pass, including direct crop equivalence and low-confidence
  recovery policy. Native harness bypasses UI taps; no new UI automation claimed.
