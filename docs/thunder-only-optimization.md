# Thunder-only mobile pipeline — 2026-09-18

Supersedes the YOLO-dependent pipeline in `thunder-first-optimization.md`.
No detector session or detector asset is loaded. The app model downloader now
fetches only Thunder. The exact former `asset/models/yolo11s-pose.onnx` was
moved to Windows Recycle Bin; historical experiment caches/weights are retained
outside app assets. Both built APK asset lists were inspected for ONNX files:
only `movenet-thunder.onnx` remains.

## Changes

- Initialize Thunder on the full square frame. Use confident torso/body joints
  to size the next crop around the hips (1.9x torso / 1.2x body extent), inspired
  by [Google's pose-derived crop example](https://www.tensorflow.org/hub/tutorials/movenet).
  This is an adaptation, not bit-exact TensorFlow crop_and_resize parity.
- Try the last successful orientation first. Search other directions at initial
  acquisition, low confidence or a rejected torso jump; no periodic sweep when
  reliable. Missing evidence is not fabricated. A continuity guard is NOT
  identity recognition and does not guarantee the intended person is selected.
- Persistent isolate retains the current frame across orientation retries.
  Transferable typed buffers replace repeated isolate spawn/frame copies.
  Crop rotation maps four bilinear sample locations once per output pixel,
  sharing those indices across RGB channels. Thunder remains 256-square int32.
- Decode the next two-second chunk concurrently with current inference, using
  two alternating files, one in-memory chunk and session-specific cancellation.
  There is no unbounded full-video raw buffer. Decode failures are returned as
  values until awaited, preventing unhandled prefetch errors.
- Timing now separates setup, decode, disk read, worker crop, crop transfer/wait,
  tensor input, Thunder invocation and tensor output. Decode overlaps inference;
  crop_worker_us is INCLUDED in crop_transfer_wait_us. Do not sum these counters
  as disjoint wall-clock stages.

## Same-device foreground Profile results

SM-S9180, 2 intra-op / 1 inter-op CPU threads. Same authorized pairs/trims,
adaptive 6/12fps and Median 0.5s / gate 0.15. One run, not a thermal-controlled
repeated benchmark. Native harness calls production code but bypasses UI taps.

| Pair | Previous optimized YOLO pipeline | Thunder only | Previous B start / speed | New B start / speed |
| --- | --- | --- | --- | --- |
| Airflare | 29.355s | 8.177s | 0.31s / 0.710x | 0.22s / 0.710x |
| Choreography | 65.715s | 18.445s | 1.48s / 1.015x | 1.54s / 1.015x |

This is about 3.6x faster than the first optimization, not a claim of realtime
operation. Relative to the earlier exhaustive Debug runs (different build mode),
155s and 407s, the improvement is much larger but not a controlled same-mode ratio.

Coverage: Airflare 96.7%, choreography 91.7%; both results remain ambiguous.
Speeds equal the prior optimized proposals, while offsets moved -0.09s / +0.06s.
Neither reference is newly matched: manually specified B values are 0s / 0.9x
and 1.2s / 1x. Spot-check images show the inverted pose is still detected, but
Airflare A's limbs have visible errors. Choreography sample A1s/B2.2s tracks the
intended central/blue-gray-pants subjects; this does not audit all crossings.

For choreography, actual crop-worker CPU time is 1.254s; crop transfer/wait
including that work is 1.417s, raw disk read 0.224s, decode work 0.925s (overlapped).
Thunder invocations now account for 15.470s over 276 calls / 144 sampled frames.
Remaining improvement should target unnecessary low-confidence orientation
retries while monitoring identity/accuracy; decode is no longer the main cost.

An earlier mixed Dozing/awake Debug pass is retained separately and EXCLUDED
from speed comparisons. Its Thunder invocations were much slower. The user
unlocked the device before the Profile rerun; power checks reported Awake.

## Verification and artifacts

- 73 Flutter tests: crop bounds, torso continuity, persistent-worker reuse,
  error recovery/close, direct rotation equivalence, legacy alignment/UI tests.
- Native cancellation during prefetch and invalid-file decode both passed.
  Zero `thunder-only-*` temporary workspaces remained after the safety tests.
- `build/thunder-only-profile.json`: fresh raw poses, all metrics and safety report.
- `build/thunder-only-dozing-debug.json`: non-comparable mixed-power-state run.
- `build/thunder-only/*-desktop-vs-phone.mp4`: same-source-time skeleton comparison,
  not playback of the differing proposed offsets. Phone destination:
  `Download/Terpsichore-Thunder-Only`.
- Restore the normal app entrypoint after testing; the delivered Profile build
  uses the normal UI rather than the native test harness.
