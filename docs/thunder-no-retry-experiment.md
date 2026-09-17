# No-direction-retry experiment — 2026-09-18

User requested another run with the retry algorithm disabled. `MoveNetAnalyzer`
now accepts `directionRetries` (default true); the native test entrypoint reads
`--dart-define=POSE_DIRECTION_RETRY=false`. This experiment disables ALL direction
search, including initial acquisition: one Thunder invocation per sampled frame,
always original orientation. Pose-derived ROI update/reacquisition is retained.

Same authorized pairs, foreground/Awake SM-S9180, Profile CPU, auto 6–12fps,
Median 0.5s / confidence 0.15 and independent B-offset/rate search. Fresh inference,
not cached skeleton reuse. Auto-sampling policy is unchanged, but its decisions
depend on predictions; this changes the sampled-frame counts between variants.
Therefore this is an end-to-end policy comparison, not fixed-frame evidence.

| Pair | With retries | No retries | Retry B start / rate | No-retry B start / rate |
| --- | --- | --- | --- | --- |
| Airflare | 8.177s | 5.435s | 0.22s / 0.710x | 0.21s / 0.705x |
| Choreography | 18.445s | 8.294s | 1.54s / 1.015x | 1.20s / 0.765x |

No-retry A/B sample counts: Airflare 16/48; choreography 43/77. Native assertions
confirmed exactly these Thunder call counts, so no hidden inference retries
occurred. Retry baseline sample counts were 16/45 and 67/77 respectively.

Airflare effective comparison coverage fell from 96.7% to 91.7%. At source
A0.35s/B0.90s both pipelines still show inverted skeletons; no-retry is not
universally unable to detect inversion. This numerical result remains far from
the manual 0s / 0.9x reference.

Choreography comparison coverage fell from 91.7% to 65%; rate 0.765x is materially
worse than the manual 1x reference, despite the matching start. A1s/B2.2s sample
images show skeleton differences, but those snapshots alone don't identify the
root cause of the full-sequence failure. Both no-retry proposals are ambiguous.
Do not claim that all quality loss is proven to come from orientation alone;
crop tracking and adaptive sampling also respond to the changed predictions.

The test is not promoted to the app default. Normal Profile app restored with
direction retry enabled and configurable FPS retained. 74 Flutter tests pass;
native cancellation/decode-error checks pass, with zero leftover temp workspaces.

Artifacts:
- `build/thunder-no-retry-profile.json`: native results/counters and safety checks.
- `build/thunder-no-retry/*-retry-vs-no-retry.mp4`: both mobile pipelines at the
  same manually mapped source times, NOT playback of the proposed alignments.
- Phone folder: `Download/Terpsichore-Thunder-No-Retry`.

Render with `tools/render_thunder_device.py --report build/thunder-no-retry-profile.json
--reference-phone build/thunder-only-profile.json --out build/thunder-no-retry`.
