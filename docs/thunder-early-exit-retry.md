# Early exit direction retry experiment

Extends the user-validated core gate; no temporal repair. Constructor flag `earlyExitRetries`, initially disabled pending measurements. Harness flag `--dart-define=POSE_CORE_GATE=true --dart-define=POSE_EARLY_EXIT=true`.

- First sample still evaluates all directions because there is no trusted previous core.
- Retain the latest measured candidate score per direction; try untried directions in descending score order (deterministic direction-number tie break). Scores may be stale; this is ordering only, not candidate acceptance.
- After each retry, stop when best candidate passes the unchanged core stability test, has at least eight body joints >= 0.3 confidence, and mean body confidence >= 0.45. Otherwise retain all three fallback calls.
- Existing candidate ranking, missing-frame policy, crop reuse, adaptive sampling, median filter and alignment solver unchanged.
- Counters `early_exit_frames` and `avoided_direction_calls` describe local saved attempts, not counterfactual whole-video savings because downstream crops can change.

80 Flutter tests passed; analyze clean.

## Results: not promoted

`build/thunder-early-exit-profile.json`: Airflare 6.898 s / 93 calls, B start 0.21 rate 0.73; Choreo 16.467 s / 248 calls, B start 1.77 rate 0.885. Choreo regressed relative to the validated core-gate's 15.478 s, 231 calls, 1.54 / 1.015. Early choice changed later crops and increased retries; local early exits do not guarantee whole-sequence savings. `earlyExitRetries` remains false in the app. Native cancellation/error cleanup passed.

Important comparison caveat: historical no-retry choreo sampled 120 frames while the validated core gate sampled 144, despite identical adaptive FPS configuration. Thus achieving identical wall time needs both fewer retries and accounting for the extra valid-motion samples. Do not claim fixed-input inference speedup from adaptive end-to-end timing alone.
