# Core grace and stage timing

Normal app enables core gating plus `coreGraceRetries`; early exit and two-pass repair are OFF. Full candidate ranking remains unchanged. Grace requires >=3 shared finite torso joints with confidence >=0.2, source delta <=0.2 s, and maximum shared-joint displacement <= previous shared torso diameter (floor0.08) * (0.25 + 1.5*dt). At least six visible body joints still required. No more than two consecutive grace frames before a strict check/full retry. This is a bounded geometric relaxation, not identity recognition or guaranteed limb accuracy.

Foreground SM-S9180 Profile, `build/thunder-core-grace-profile.json`, native status complete. Same manual fixtures, adaptive FPS, median0.5. Baseline user-reviewed report `build/thunder-core-gated-profile.json`.

| Pair | User-reviewed core gate | Grace | Calls | Sampled frames | B start / speed |
| --- | ---: | ---: | --- | --- | --- |
| Airflare | 7.794s | 6.732s | 106→91 | 61→64 | 0.22 / 0.730 |
| Choreo | 15.478s | 13.490s | 231→201 | 144→144 | 1.51 / 1.020 |

Approximately 13.6%/12.8% further wall-time reduction in single runs, not repeated statistical measurements. Airflare comparison coverage96.7%; Choreo93.3%. Both ambiguous. Manual Airflare0.9 still not matched. Choreo output close to prior1.015 but not identical. Spot-checked choreo A1,3,4.5s: core remains on intended subject, limb estimates differ. Not an exhaustive annotation.

Fresh core-gate rerun with identical added timers: `build/thunder-core-gate-stages-profile.json`, complete, 7.666s Airflare /15.605s Choreo, same106/231 calls and previous proposals. Compared to this same-turn run, grace saves12.2%/13.6%. Device awake throughout both runs. Latest full suite81 tests passed and analyze clean.

## Timings (seconds, A+B sums)

| Stage | Airflare | Choreo |
| --- | ---: | ---: |
| Session/worker setup | .188055 | .062216 |
| Decoder elapsed, overlaps other work | 1.430886 | .896835 |
| Raw file read | .085787 | .242004 |
| Crop worker + transfer/wait | .447008 | 1.010225 |
| Worker compute, subset of preceding row | .394805 | .900603 |
| Input tensor creation | .200829 | .424917 |
| First inference per sample | 3.560904 | 8.014947 |
| Retry inference | 1.543651 | 3.131409 |
| Output tensor read | .052384 | .107506 |
| Decode/restore keypoint coordinates | .001169 | .002779 |
| Core gate (including grace) | .000398 | .000837 |
| Median filter | .007228 | .005857 |
| Alignment search | .091711 | .130726 |
| Total observed workflow (ms granularity) | 6.732 | 13.490 |

`session.run` includes invocation boundary overhead, not isolated accelerator time. Input/output tensors and crop transfer are measured separately. Decode overlaps inference: do not sum it with all other rows. Worker compute is already included in crop wait. Residual time includes waiting for initial decode, candidate scoring/selection, adaptive sampling, crop update, progress callbacks, disposal/cleanup, and scheduling; these have not all been separately instrumented. End-to-end harness does not measure user taps, UI rendering, model asset download, preview playback, or export.

Choreo Thunder run sum11.146s = ~82.6% of total; retries3.131s = ~23.2%. First-call model work alone8.015s, with144 sampled frames. Historical no-retry8.294s used120 samples, so subtracting retry time does not reproduce that older run. This optimization has not reached no-retry speed.

## Enabled processing

1. Decode and sample, scale/pad to640; crop/rotate/resize to256, RGB int32 tensor (preprocessing).
2. Restore17 model keypoints to original video coordinates; confidence checks, core continuity/candidate selection, next crop (online tracking, not smoothing).
3. Centered coordinate median0.5 source seconds (user-configurable0–1s), confidence>=.15, minimum3 samples. Do not cross missing-joint observations or adjacent gaps>0.2s; do not invent missing joints. Original confidence retained.
4. Pose normalization, temporal feature interpolation, position/direction comparison, coarse/fine B start and speed search. This is alignment, not skeleton smoothing.

No Kalman/One Euro filtering, no two-pass repair, no legacy `smoothPoseSequence` filling in this active workflow. The skeleton preview can interpolate neighboring available frames; preview rendering is outside this inference benchmark.

Native prefetch cancellation/decode-error cleanup passed; zero leftover workspaces. Videos compare previous core gate vs grace at matching manual source times (both median0.5), not automatically aligned playback.
