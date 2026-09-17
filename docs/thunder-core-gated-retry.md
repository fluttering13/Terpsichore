# Core-gated direction retries

Based on the original online direction-retry analyzer, not the failed two-pass repair experiment. `temporalRepair` remains false. App default now enables `coreGatedRetries`; device harness build flag `--dart-define=POSE_CORE_GATE=true` (harness explicitly defaults false to preserve baseline).

The core is the geometric mean of COCO shoulders and hips (5, 6, 11, 12), not physical center of mass. All four must have finite coordinates and confidence >= 0.3. Use the same joints in both frames to avoid center shifts caused by changing visibility.

Fast path requires:

- Previous accepted pose within 0.3 source seconds; first frame always searches directions.
- At least six body keypoints with confidence >= 0.2.
- Shoulder-midpoint to hip-midpoint length ratio between 0.65 and 1.55 (length floor 0.08, in image-height units).
- Core displacement <= previous torso length * (0.25 + 1.5 * dt), using source timestamp delta and aspect-corrected coordinates.
- Existing same-subject safety guard still passes.

If fast path fails, evaluate the other three rotations, as in the baseline. Candidate scoring and acceptance remain unchanged. A moving/low-confidence limb alone no longer triggers direction retries. A core failure is a retry trigger, not an additional reason to erase a pose. There is no second decode pass or second-pass deletion of suspect frames.

These geometric checks cannot prove identity when people overlap or move smoothly into each other's positions. They also do not verify limb accuracy. This experiment separates retry-trigger changes from candidate-scoring changes so the comparison is interpretable. Native run reports include `core_gated_retries`, `retry_frames`, and `core_skipped_retry_frames`.

## Verification status

78 Flutter tests pass and `flutter analyze` is clean. Profile harness retained at `build/thunder-core-gated-harness-profile.apk`.

## Fresh foreground comparison on SM-S9180

Reports `build/thunder-core-gated-profile.json` and `build/thunder-original-core-comparison-profile.json`, both complete. Core gate ran first, baseline second; single run per variant, not a repeated statistical benchmark. Both used adaptive sampling and generated identical frame counts (61 Airflare / 144 Choreo). Phone awake before and after. No two-pass repair.

| Pair | Original total | Core gate total | Calls original → core | B start / rate (both) |
| --- | ---: | ---: | ---: | --- |
| Airflare | 8.112 s | 7.794 s | 112 → 106 | 0.22 / 0.710 |
| Choreo | 18.617 s | 15.478 s | 276 → 231 | 1.54 / 1.015 |

Total includes A+B analysis and median/solver. Approximately 3.9% / 16.9% wall-time reduction. Choreo A calls 172 → 118, B 104 → 113: core motion can trigger additional retries even where old limb-confidence criteria passed. Net savings are 45 calls, not a guarantee of savings in every clip.

Airflare coverage unchanged at 96.7%; Choreo comparison coverage 91.7% → 98.3%. Coverage measures usable solver comparisons, not identity accuracy. All proposals remain ambiguous; Airflare still differs from manual B rate 0.9, and Choreo start still differs from manual 1.2. This optimization preserves these two baseline proposals, not universal output equivalence.

Native cancellation during prefetch, decode error, and zero-leftover-workspace checks passed for both runs. Rendered MP4s decode successfully. Comparison videos at manually matched source times, both median 0.5 s, are in phone `Download/Terpsichore-Thunder-Core-Gate`. Spot checks at choreo source A 1, 3, 4.5 seconds show the intended core with varying limb estimates; no claim of exhaustive identity verification.

Promoted core gate to normal app default following this comparison; original candidate ranking, full rotation fallback, UI skeleton toggle and sampling FPS remain intact.
