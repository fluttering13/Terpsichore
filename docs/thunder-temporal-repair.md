# Thunder two-pass continuity experiment

Experimental constructor flag `temporalRepair`, default false; app default remains unchanged.
Native harness: `flutter build apk --profile -t test/device/thunder_pairs.dart --dart-define=POSE_DIRECTION_RETRY=false --dart-define=POSE_TEMPORAL_REPAIR=true`.

## Implemented scope

- First pass: existing adaptive 6–12 FPS sampling and crop tracking, one unrotated Thunder call per sampled frame.
- Whole-sequence audit: median displacement of at least six common confident body joints, normalized by previous torso length (floor 0.08 image-height units). Threshold `0.35 + 2.5 * min(abs(dt), 0.25)`; joint confidence >= 0.2. Require a visible shoulder and hip. One limb alone does not flag the frame.
- Audit retains the last trusted anchor instead of propagating a suspect frame.
- Second pass follows the sequence again, locally replacing flagged frames using the last trusted crop, then 1.35x crop expansion. Not a tensor-batched model invocation; the model remains batch size 1.
- Candidate must satisfy backward continuity and, when next frame passed the audit, forward continuity. Early accept at cost <= 0.6; otherwise accept best cost <= 1.
- At most two attempts per frame, total extra calls <= ceil(sampled frames / 2). Failed or budget-exhausted suspect frames become zero-confidence missing evidence; no interpolation across failures added here.
- Re-decode only needed original chunks, preserving the original timestamp grid; one decoded chunk resident at a time. Existing cancellation and workspace cleanup apply.

## Limitations

This first experiment uses the last trusted crop, not velocity extrapolation, appearance embeddings, global identity tracking, or rotation retries. A smoothly wrong initial subject cannot be identified by continuity alone. A long run of failures can consume the global budget; there is no independent segment-duration budget. A future frame is only used when already supported by the first audit, so this is not global bidirectional optimization. Thresholds have not been tuned to the user's manual alignment speeds.

Adaptive sampling can choose different frame counts as predictions change. Historical timing comparisons are end-to-end workflow comparisons, not fixed-input model microbenchmarks. Repair time includes audit and re-decoding; aggregate Thunder timing includes both passes.

## Foreground SM-S9180 Profile results

Report: `build/thunder-temporal-repair-profile.json`, status complete. Phone awake before and after measurement. Same four private fixture copies and manual trims as earlier tests. Times include A+B extraction/inference and alignment search.

| Pair | Historical all-direction fallback | Historical no retry | Two pass | First pass | Repair including audit |
| --- | ---: | ---: | ---: | ---: | ---: |
| Airflare | 8.177 s | 5.435 s | 7.917 s | 5.041 s | 2.787 s |
| Choreo | 18.445 s | 8.294 s | 10.174 s | 8.175 s | 1.856 s |

Airflare sampled 64 frames, added 25 calls, accepted 4 repairs and rejected 9 frames. Choreo sampled 120 frames, added 23 calls, accepted 2 repairs and rejected 10 frames. Acceptance means passed the geometric threshold, **not verified correct identity**. Audit alone cost 0.297 ms / 0.468 ms per pair.

Two-pass proposals: Airflare B start 0.20, speed 0.680, coverage 50%; Choreo B start 0.88, speed 0.680, coverage 58.3%, ambiguous. Manual speeds remain 0.9 / 1.0. These are worse than the existing retry baseline; do not promote this experiment to app default. Dropping suspect frames reduces useful evidence without sufficiently recovering the intended subject. Geometric continuity alone also cannot detect a smooth switch to a nearby person.

76 Flutter tests pass; analyzer clean. Native prefetch cancellation, invalid decode cleanup passed, zero leftover workspaces. Repair-specific cancellation has not been separately exercised on-device. Both rendered MP4s decode successfully and are copied to phone `Download/Terpsichore-Thunder-Two-Pass`. Videos compare NO-RETRY against TWO-PASS at the same manually mapped source times, both median 0.5 s; they do not demonstrate the proposed automatic alignment. Preview inspection is not a full identity annotation.
