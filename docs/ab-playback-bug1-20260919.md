# bug1 common playback frame validation — 2026-09-19

Three full replays on the connected Android device, using the normal A+B screen after the explicit user/programmatic seek split (08:53 local time). A: 6104–10932 ms at 1x; B: 5740–7696 ms at 0.385x; common duration: 4828 ms.

An actual drag was performed before replaying. Native logs show `scrubTo` requests only during that gesture, followed by normal `seekTo` on release. Replay requests use normal `seekTo` and start with suppression=0. The 160 ms heuristic and 220 ms inactivity timer have been removed. Programmatic seeks explicitly exit scrubbing; dragging uses a separate Pigeon API and per-operation Dart zone, without a shared mutable intent flag.

The ten checkpoints are the midpoints of ten equal common-timeline segments. The common clock follows A, as in the app. For each checkpoint, locate the corresponding original A frame in Media3 frame metadata, then compare B at the same scheduled surface release time with the frame predicted by its trim and speed. Original frame numbers are zero-based ffprobe output. Sub-millisecond timestamp rounding is tolerated. A missing checkpoint or more than one source-frame difference fails.

This measures frames submitted to the video surface; it is not a pixel comparison of the physical display. Three passing replays cannot rule out every intermittent decoder failure.

| Part | Common ms | Expected A | Actual A (all runs) | Expected B | B run 1 | B run 2 | B run 3 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 241.4 | 152 | 152 | 174 | 174 | 174 | 174 |
| 2 | 724.2 | 163 | 163 | 179 | 179 | 179 | 179 |
| 3 | 1207.0 | 175 | 175 | 185 | 185 | 185 | 185 |
| 4 | 1689.8 | 187 | 187 | 190 | 191 | 191 | 191 |
| 5 | 2172.6 | 198 | 198 | 196 | 196 | 196 | 196 |
| 6 | 2655.4 | 210 | 210 | 202 | 202 | 202 | 202 |
| 7 | 3138.2 | 221 | 221 | 207 | 207 | 207 | 207 |
| 8 | 3621.0 | 233 | 233 | 213 | 213 | 213 | 213 |
| 9 | 4103.8 | 244 | 244 | 218 | 218 | 218 | 219 |
| 10 | 4586.6 | 256 | 256 | 224 | 224 | 224 | 224 |

Result: 30/30 checkpoints passed. A matches all expected source frames; B differs by at most one original frame (approximately 33 ms in source time, 86 ms on the shared timeline). This is not a claim of frame-exact synchronization.

Reproduction: enable `adb shell setprop log.tag.AB_FRAME DEBUG`, reopen the project, play to the end and replay three times, then run `python tools/verify_ab_frames.py`. Disable diagnostics with `adb shell setprop log.tag.AB_FRAME INFO` and restart the app. Detailed log and JSON are written under `build/ab-frame-mapping/`.
