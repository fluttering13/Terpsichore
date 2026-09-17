# Saved model proposals versus manual alignment

Computed with `tools/compare_pose_manual_results.py`; no new inference or production backend change.
Inputs: `build/pose-onnx-clean-profile.json`, `build/pose-alternatives-profile.json`
(excluding duplicate ONNX), `build/pose-mlkit-check-profile.json`.
Each configuration has two runs per case, fixed 12 FPS and median window 0.5 seconds.

## Reference and metric

- Airflare: A 0–1.3 seconds at 0.35x; B 0–4.2 at 0.9x.
- Choreo: A 0–5.7 seconds at 1x; B 1.2–7.2 at 1x.
- A and selected B end remain fixed in this comparison.

For elapsed A playback time t, compare B source timestamps `b_start + b_rate*t`
against the manual mapping. Integrate their absolute difference over the manual A
playback duration (1.3/0.35 and 5.7 seconds respectively), then divide by duration.
This is an unclamped linear time-map metric: it does not simulate stopping/looping
at B's trim end. Unit is B-source seconds, not wall-clock playback seconds.
Score each repeat separately, average within each case, then give both cases equal
weight. Do not average parameters first, and do not use the solver's own pose loss
as a ground-truth score. Offset and rate can partially compensate; parameter errors
are also emitted by the script. This metric does not measure skeleton accuracy.

## Results (lower is closer)

| Configuration | Airflare MAE (s) | Choreo MAE (s) | Equal-case mean (s) |
| --- | ---: | ---: | ---: |
| ML Kit Accurate STREAM parallel | 0.184 | 0.302 | 0.243 |
| ML Kit Base STREAM sequential | 0.219 | 0.303 | 0.261 |
| ML Kit Base STREAM parallel | 0.228 | 0.318 | 0.273 |
| ML Kit Accurate STREAM sequential | 0.177 | 0.372 | 0.275 |
| Thunder FP16 LiteRT parallel | 0.254 | 0.298 | 0.276 |
| ML Kit Accurate SINGLE_IMAGE parallel | 0.253 | 0.313 | 0.283 |
| Current Thunder ONNX parallel | 0.243 | 0.342 | 0.292 |
| ML Kit Base SINGLE_IMAGE parallel | 0.265 | 0.347 | 0.306 |
| Thunder INT8 LiteRT parallel | 0.214 | 0.400 | 0.307 |

Accurate STREAM parallel has the lowest equal-case average in these saved runs,
approximately 17% below current ONNX. Its pair processing totals average 2.051 s
Airflare and 2.417 s Choreo. These are whole-pipeline times, not inference-only.
FP16 has the lowest Choreo average, but its 0.004 s advantage over Accurate STREAM
parallel is too small to infer a reliable general advantage from two runs.
Accurate STREAM sequential has the lowest Airflare average.

## Parameter-level caveats

- Accurate STREAM parallel Airflare proposals: start 0.29 / rate 0.725 and start
  0.42 / rate 0.680; manual start 0 / rate 0.9. Choreo: 1.39 / 1.035 and
  1.40 / 1.040; manual 1.2 / 1.0.
- All alternatives' Airflare rates remain 0.680–0.730, substantially below 0.9.
  No method reproduces the manual airflare alignment adequately yet.
- INT8 Choreo rate is 1.0, but start is 1.60 instead of 1.20: a constant 0.4 s
  source-time offset. Matching speed alone does not establish alignment quality.
- STREAM proposals varied across repeats even with sequential processing. The
  cause is not isolated; do not attribute this solely to parallel execution.
- ONNX, FP16, INT8 and SINGLE_IMAGE proposals reproduced across these two rounds;
  this is not proof of determinism across all runs/devices.
- Only two user examples and two repeats; no statistical superiority claim or
  whole-video person-identity accuracy evaluation. Existing comparison videos show
  skeletons at manual timestamps, not automatically proposed playback alignment.

Keep the approved production backend unchanged. Accurate STREAM is the leading
candidate for further alignment/repeatability evaluation; INT8 remains a speed
and integration candidate, not the closest-to-manual winner on these examples.
