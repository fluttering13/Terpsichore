# User-selectable pose sampling FPS

A+B → AI alignment settings → 骨架採樣 FPS.

- Default Auto preserves the prior adaptive 6–12fps behavior.
- Fixed choices: 6, 8, 12, 15, 24, 30fps. Fixed means no adaptive frame skipping.
- Stored as `samplingFps` in app-support `pose_settings.json`; 0 means Auto.
  Missing or unsupported persisted values fall back to Auto.
- Changing FPS clears both tracks' raw/processed pose caches and analyzed time
  bounds. Existing video trims/speeds are not changed; rerun AI for a new result.
- FFmpeg extraction, source timestamps and progress all use the selected FPS.
  Chunk duration is capped at min(2 seconds, 24/FPS) to keep raw buffers bounded.
- Playback/export frame rate is independent of this setting. Higher sampling
  preserves finer temporal evidence but cannot guarantee more accurate poses.
  Runtime is not necessarily linear in FPS: cold setup and direction retries
  also contribute. The minimum of 6fps fits the current gap/median policies.

Validation: 74 Flutter tests pass (including dropdown selection and invalid
native-API FPS rejection). `test/device/thunder_fps.dart` verified exactly
6/12/30 frames and timestamps i/FPS for a one-second authorized Airflare clip,
including the 30fps multi-chunk boundary. Native report:
`build/thunder-fps-result.json`. This is extraction correctness testing, not
a held-out quality benchmark or a UI persistence automation test.

## Current remaining bottleneck

From the latest full choreography foreground Profile run (Auto, 18.445s):
A has 67 sampled frames but 172 Thunder calls; B has 77 frames but 104 calls.
The current loop tries three additional directions when initial acquisition,
low-confidence pose, or the torso-continuity guard triggers. Thus A has 35
four-direction frames and B has 9; 132 of 276 calls are additional retries.
Thunder invocation time totals 15.470s, ~84% of total wall time. Other work is
~2.975s. The counters don't distinguish low-confidence from continuity-triggered
retries, so attributing all retries specifically to occlusion would be speculation.
Separate visibility/occlusion handling from orientation recovery before further
reducing FPS solely to compensate for unnecessary direction searches.
