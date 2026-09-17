# Human-reference alignment experiment — 2026-09-18

This is an offline Python/ONNX CPU experiment, not a deployed app change or a
phone performance benchmark. All four clips stayed on the local PC/phone.

## Reference cases

| Case | A source interval / speed | B source interval / speed |
| --- | --- | --- |
| Airflare | SaveClip.App_AQO1…-U_1.mp4, 0–1.3s / 0.35x | Camera/20260911_204604_1.mp4, 0–4.2s / 0.9x |
| Choreography | DCIM/教學/GameStarTs 課程內容_720p_1_1.mp4, 0–5.7s / 1x | Download/A3_1.mp4, 1.2–7.2s / 1x |

The user confirmed the Airflare A filename. It is the previous A, but B is a
DIFFERENT recording from the previous 20260915 experiment.

Equal-duration fitting would force B to 1.1308x and 1.0526x respectively, so it
cannot reproduce both the supplied trims and speeds. This experiment treats
trims as available bounds, and fits an affine correspondence independently:
`B(t) = B_start + playback_elapsed * B_rate`; A and its speed remain fixed.
B's end trim is not changed or presented as a newly inferred endpoint.

## Methods and controls

Same pinned detector/RTMPose-S/RTMPose-M-WholeBody files and decoder functions
as tools/benchmark_pose_candidates.py. Sampling is 12fps, using source time.

- Local: initial largest person then IoU/size-gated continuity.
- Global: Hungarian association of IoU and HSV appearance histograms; select a
  persistent large/confident track using the whole clip. This is a lightweight
  prototype, NOT ByteTrack/BoT-SORT or learned ReID.
- Rotation-global (Airflare): 0/90/180/270 degree detector + pose candidates,
  inverse-map to original coordinates, select orientation by sequence-level
  confidence/continuity rather than independent frame confidence.
- WholeBody-global: alternative model, but uses its common COCO-17 body joints
  for controlled matching. Extra hand/foot landmarks are NOT used yet.
- Bone-direction variants: confidence-weighted normalized limb directions,
  replacing hip/torso-normalized joint positions.

The local variant is a conceptual baseline, not a bit-identical app reproduction:
the desktop image preprocessing and experimental objective differ. No temporal
gap filling is used here; in particular synthetic preview joints do not count as
evidence. Confidence 0.3 is not calibrated identically across different models,
so null WholeBody results do not establish that the model is intrinsically worse.

Search: B speed 0.1–4x; B start within +/-10% of selected B length, clipped at 0.
Coarse 0.05 speed / 0.05s start, five distinct seeds, fine 0.005 speed / 0.01s.
Score combines robust position/direction discrepancy and missing evidence.
Require >=80% source-bound coverage of A playback, >=60% of B source span,
and >=50% comparison samples having at least six usable body joints/bones.
These are experimental thresholds, NOT the production acceptance policy.
Reference B speed is accessed only after search to report error. Two synthetic
tests verify independent parameter recovery, missing-data rejection and that
changing the reference speed cannot change the optimizer's prediction.

## Results

| Case / approach | B start | B speed | Speed error | Start error |
| --- | ---: | ---: | ---: | ---: |
| Airflare local / global / WholeBody-global / nonrotated bones | — | — | rejected: insufficient evidence | — |
| Airflare rotation-global | 0.28s | 0.680x | -24.44% | +0.28s |
| Airflare rotation + bones | 0.28s | 0.680x | -24.44% | +0.28s |
| Choreography local | 1.39s | 1.040x | +4.0% | +0.19s |
| Choreography global | 1.58s | 0.985x | -1.5% | +0.38s |
| Choreography WholeBody-global | 1.58s | 1.000x | 0% | +0.38s |
| Choreography global + bones | 1.59s | 0.985x | -1.5% | +0.39s |

Airflare 0.680x lies almost exactly at the 60% B-span coverage floor
(`4.2 * 0.6 / (1.3/0.35) = 0.67846`). It is explicitly flagged as unreliable,
not accepted as a solution. Rotations improve usable torso-feature frames from
A 7/16 and B 27/51 to A 14/16 and B 43/51, but that does NOT prove better timing.

Choreography global improves usable feature frames from A 57/69, B 75/87 to
A 67/69, B 81/87. Inspection of the 1s preview shows the intended central dancers
rather than the foreground crossing person, but this is not an exhaustive ID-switch
audit. Matching B speed alone is insufficient: WholeBody still leads the manual
correspondence by 0.38 B-source seconds throughout. Global's start bias is larger
than the local variant's. No approach has matched the complete manual result yet.

## Review artifacts

- `build/manual-alignment/report.json`: numeric results including B-source
  correspondence error, sample coverage and warnings.
- `airflare-manual-vs-predicted.mp4`: manual pair vs rotation-global proposal.
- `choreo-manual-vs-predicted.mp4`: manual pair vs RTMPose-S global proposal.
- Four panels: MANUAL A, MANUAL B, PREDICT A, PREDICT B. A is deliberately
  repeated for side-by-side timing comparison. Original reference A speed;
  no audio; skeletons drawn from nearest inference sample, not smoothed.

Candidate extraction took approximately 8.66 / 36.70 / 21.64 / 21.04 seconds for
Airflare A/B and choreography A/B on desktop CPU. This pools multiple people,
models and rotations, so it is NOT an individual model's latency. Cached reruns
only repeat tracking/features/search. Clear or relocate the experiment's candidate
cache if inputs/models/preprocessing change; it currently does not fingerprint
the cache automatically.

## Next justified experiment

Keep global subject tracking, but do NOT promote it as a complete alignment fix.
Next compare motion-event phase matches (hand support changes, torso inversion,
limb-opening extrema for Airflare; motion-direction reversals for choreography)
and robust affine fitting from multiple correspondences. Reject short/static or
constraint-boundary matches. Preserve manual crop bounds as soft priors, not a
forced equal-duration constraint. Evaluate on additional clips before tuning
weights around these two examples. App behavior remains unchanged by this work.

Run with a Python environment providing numpy, scipy, opencv-python, onnxruntime:

```powershell
python tools/benchmark_manual_alignment.py
python tools/test_manual_alignment.py
python tools/render_manual_alignment.py
```
