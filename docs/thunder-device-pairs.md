# Fresh Android Thunder pair test — 2026-09-18

Device: Samsung SM-S9180, serial R5CWC1Z5EJM. Debug build, CPU ONNX Runtime,
two intra-op / one inter-op threads. This is one fresh run, not a repeated
latency benchmark. Times include session loading, FFmpeg decode, tensor
preparation, person detection, pose inference and tracking. They are not
individual model-call latency.

`test/device/thunder_pairs.dart` calls the production `MoveNetAnalyzer`,
`medianPoseSequence` and `solveThunderAlignment`. No cached skeleton is supplied
to inference. The harness uses app-private copies of the four authorized local
video fixtures and preserves user projects/settings. It bypasses file-picker
and button interactions; this is a native pipeline test, not a UI automation test.

## Inputs and controls

- Airflare A: confirmed SaveClip AQO1, 0–1.3s, 0.35x; B:
  `20260911_204604_1.mp4`, anchors 0–4.2s. B inference includes the app's
  expanded search interval, 0–4.245s, clamped to video duration.
- Choreography A: GameStarTs, 0–5.7s, 1x; B: `A3_1.mp4`, anchors 1.2–7.2s.
  B inference interval is 0.6–7.249s (10% search margin, duration-clamped).
- Both: four-orientation mobile inference, 12fps, Median 0.5s, confidence
  0.15, start radius 10%, B speed 0.1–4x. A fixed; B end retained.
- Desktop reference is the retained **post-processed experiment**, not the
  manual label. Manual labels are Airflare B 0s / 0.9x and choreography
  B 1.2s / 1x.

## Interpretation

Both cases completed without an inference exception. Fresh phone results are
close to, but **not identical to**, the desktop experiment. Both proposals are
ambiguous and neither establishes correct subject tracking throughout the clip.

| Case | Desktop B start / rate | Phone B start / rate | Manual B start / rate | End-to-end phone time |
| --- | --- | --- | --- | --- |
| Airflare | 0.26s / 0.715x | 0.35s / 0.710x | 0s / 0.900x | 155.043s |
| Choreography | 1.51s / 0.990x | 1.50s / 1.005x | 1.2s / 1.000x | 406.659s |

Airflare A: 36,063ms / 16 frames; B: 118,829ms / 51 frames; post/search:
151ms. Choreography A: 179,972ms / 68 frames; B: 226,524ms / 80 frames;
post/search: 163ms. Native coverage was 96.7% and 91.7%, respectively; these
are usable comparison-frame fractions, not accuracy percentages.

Spot-check of exported comparison images at Airflare A0.35/B0.90s and
choreography A1.00/B2.20s shows broadly similar skeletons, with visible joint
coordinate differences. This is not a full-video identity audit. Both generated
videos passed full FFmpeg decode checks and were delivered to
`Download/Terpsichore-Thunder-Device`. Normal app APK is restored after the test.

The cached-evidence Dart parity test reproduced the desktop offset/rate, but
that establishes only filter/search parity. Fresh mobile evidence can differ:

- Desktop uses original-resolution images before person crops. Mobile first
  makes a 640-square letterboxed image; Thunder input remains 256-square.
- Mobile retains the initial-largest-person / IoU tracker with local direction
  selection. Desktop uses a global appearance tracker and sequence selection.
- Desktop choreography used only upright inference; mobile tries all rotations.
- Mobile B is extracted over the UI search interval, with two-second decode
  chunks. Desktop evidence was extracted from zero; sampling phase can differ.

These are known implementation differences, not a controlled attribution of
how much each difference changes the result. The native result's `ambiguous`
flag must be retained; high skeleton coverage does not establish correct identity.

Artifacts: `build/thunder-pairs-device.json` contains native raw skeletons,
per-track times, search times and results. `tools/render_thunder_device.py`
renders desktop/phone skeletons at identical manually mapped source times;
these videos compare skeleton evidence, **not the two proposed playback rates**.
