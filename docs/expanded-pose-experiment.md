# Expanded pose-model experiment (2026-09-18)

Offline desktop CPU experiment; no production app/model changes. Inputs stayed
on the PC and the user's phone; no video was uploaded to Hugging Face.

## Inputs and reference

The two pairs are the confirmed inputs in `manual-alignment-experiment.md`:

- Airflare: `SaveClip.App_AQO1…-U_1.mp4` A 0–1.3s at 0.35x;
  `20260911_204604_1.mp4` B 0–4.2s at 0.9x.
- Choreography: `GameStarTs 課程內容_720p_1_1.mp4` A 0–5.7s at 1x;
  `A3_1.mp4` B 1.2–7.2s at 1x.

These are not the older `20260915_213728_1.mp4` smoothing-test pair.

## Models and sources

This is a comparison of seven architecture families, not fifteen independent
architectures. Different sizes of one family are labelled as variants.

| Family | Variants | Source / inference approach |
| --- | --- | --- |
| RTMPose | S, M, L, X, M-WholeBody | [HF weights](https://huggingface.co/bukuroo/RTMPose-ONNX); YOLO11s person proposals + SimCC pose |
| YOLO Pose | YOLO11s, YOLOv8n/s/m | [YOLO11 HF](https://huggingface.co/AXERA-TECH/YOLO11-Pose), [YOLOv8 HF](https://huggingface.co/Xenova/yolov8-pose-onnx); joint detection/pose |
| LitePose | S COCO | Existing local experiment asset; associative-embedding decoder |
| ViTPose+ | Small FP32 | [HF ONNX](https://huggingface.co/onnx-community/vitpose-plus-small-ONNX); transformer pose on YOLO11s person crops |
| MoveNet | Lightning, Thunder FP32 | [Lightning HF](https://huggingface.co/Xenova/movenet-singlepose-lightning), [Thunder HF](https://huggingface.co/Xenova/movenet-singlepose-thunder); single-person models, here applied to YOLO11s person crops |
| BlazePose / MediaPipe | OpenCV Zoo FP32 export | [Pose HF](https://huggingface.co/opencv/pose_estimation_mediapipe), [Detector HF](https://huggingface.co/opencv/person_detection_mediapipe); native BlazePose detector, no YOLO dependency |
| HRNet | W32 COCO FP32 | [Qualcomm HF](https://huggingface.co/qualcomm/HRNetPose/tree/416b07df7f0ba6961abe328a6687e48da2f3ed88); parallel high-resolution CNN streams, YOLO11s person crops |

Downloaded weights are pinned by repository revision and verified against the
HF SHA-256 metadata. `build/pose-candidates/expanded-sources.json` and
`diverse-sources.json` retain provenance; downloader scripts pin the revisions.
Original assets have their SHA-256 in the benchmark results. Remote repository
Python code is not loaded with `trust_remote_code`.

ViTPose preprocessing and UDP/DARK heatmap decoding use the official
`transformers==4.49.0` implementation. DARK is spatial heatmap decoding, not
temporal smoothing. MoveNet follows the [official RGB/int32 and normalized y/x
contract](https://www.tensorflow.org/hub/tutorials/movenet), using a square
1.25-padded person crop instead of its single-person full-frame dynamic crop.
BlazePose follows the OpenCV Zoo input/output contracts, with generated SSD
anchors and a single hip-centered affine ROI warp. It omits optional heatmap
refinement, segmentation and world-coordinate outputs. This is an ONNX adapter,
not a bit-identical run of the MediaPipe Tasks video tracker. HRNet uses the
Qualcomm v0.32.0 RGB 0–1 contract (normalization is inside the model), standard
1.25-padded affine crop and quarter-pixel heatmap decoding. [Sapiens](https://huggingface.co/facebook/sapiens-pose-0.3b) was also
found on HF but is not included in the measured set; this round prioritizes
smaller mobile-oriented candidates over high-resolution foundation models.

## Measurement and limitations

- Windows, Intel Core i9-14900F, ONNX Runtime 1.30.0 CPUExecutionProvider,
  intra-op 2 / inter-op 1 threads, batch 1, three warmups per model. Models are
  benchmarked sequentially. This is exploratory desktop timing, **not phone
  timing**, GPU/NPU timing, or a thermally controlled benchmark.
- Sample every 1/12 source second. 16/51 Airflare frames and 69/87 choreography
  frames. Decode, alignment search and video encoding are outside timed frames.
- `pose_call`: ORT forward only, per person for top-down models; whole-image
  detector+pose for YOLO/LitePose. These are different units of work.
- `detector_call`: separate ORT forward for top-down/native BlazePose detector.
- `pipeline_frame`: rotations, detection, up to five people, crop/normalization,
  pose inference, decoding, inverse coordinate transforms and appearance
  histograms. Excludes the subsequent global track selection and search.
- Each result contains count, mean, median and p95 for each clip. Do not convert
  the per-person `pose_call` alone into application FPS.
- Raw = original image orientation, no temporal smoothing/gap filling. All
  approaches still use a common experimental global person-track selector.
- Airflare additionally has `rot4`: 0/90/180/270 degrees, detector+pose in each,
  followed by global orientation/track selection. Native BlazePose already
  rotates its detected ROI in the raw pass. The extra four passes are charged
  to pipeline time. Rotations are not a free accuracy improvement.
- Compare common COCO-17 body joints. Extra WholeBody/BlazePose joints are not
  used to give one model an unfairly different alignment descriptor.
- Confidence >=0.3 is shared but **not calibrated between models**. Feature
  availability is not keypoint accuracy. There are no manually labelled joint
  positions or identity tracks, so do not present these results as PCK/mAP or
  a verified identity-switch count.
- Person tracking is the same IoU/HSV Hungarian prototype as the previous
  experiment, not a trained ReID tracker. Model differences can alter which
  persistent person is selected; preview videos are required to audit that.
- Same independent affine alignment objective as the prior experiment. A is
  fixed; B start is searched within 10% of selected B duration; B rate 0.1–4x.
  B end stays a trim bound. Supplied rates are used only after optimization for
  evaluation. Matching rate alone is not matching timing: also inspect start
  bias and mean B-source mapping error. Boundary minima are flagged unreliable.
- No production smoothing is mixed into this model comparison; skeleton videos
  explicitly say `no smoothing`. They do not claim to be a new smoothing test.

## Measured results

All 15 variants completed all three case/mode combinations (45 result rows).
The following is **choreography B, raw orientation**, not an average across
different workloads. ORT-only latency is per person for top-down models and
per image for YOLO/LitePose. The native/shared detector is additional where
listed. Different runs show noticeable host-time variation even for the same
YOLO detector; treat these as exploratory measurements, not precise device
rankings. Full per-clip counts, medians and p95 are in the CSV/JSON.

| Model | Pose ORT p50 ms | Pose ORT p95 ms | Detector ORT p50 ms | Pipeline p50 ms/frame |
| --- | ---: | ---: | ---: | ---: |
| RTMPose-S | 6.1 | 7.7 | 95.6 | 113.5 |
| RTMPose-M | 20.2 | 28.7 | 138.7 | 188.7 |
| RTMPose-L | 42.3 | 56.8 | 134.1 | 225.8 |
| RTMPose-X | 129.2 | 134.7 | 96.8 | 362.1 |
| RTMPose-M WholeBody | 19.0 | 20.4 | 98.3 | 141.7 |
| YOLO11s Pose | 95.8 | 101.0 | included | 99.3 |
| YOLOv8n Pose | 41.2 | 43.6 | included | 44.7 |
| YOLOv8s Pose | 139.5 | 166.1 | included | 143.3 |
| YOLOv8m Pose | 331.5 | 388.3 | included | 335.3 |
| LitePose-S | 62.9 | 77.4 | included | 64.7 |
| MoveNet Lightning | 4.1 | 6.8 | 129.6 | 144.6 |
| MoveNet Thunder | 13.4 | 15.0 | 105.5 | 137.7 |
| BlazePose | 6.5 | 9.0 | 6.2 | 17.0 |
| ViTPose+ Small | 77.7 | 95.8 | 136.9 | 310.4 |
| HRNet-W32 | 58.0 | 74.8 | 117.6 | 243.1 |

Do not add the three medians arithmetically: there may be several people per
frame, preprocessing/decoding costs, and medians are not additive.

The new architectures' alignment proposals below use rot4 for Airflare and
raw for choreography, consistently rather than selecting each model's best
mode after looking at reference errors. `start / rate` are absolute B source
seconds and playback speed; B end remains 4.2s / 7.2s respectively.

| Model | Airflare B start / rate | Mean mapping error (s) | Choreography B start / rate | Mean mapping error (s) |
| --- | --- | ---: | --- | ---: |
| Manual reference | 0 / 0.900x | — | 1.2 / 1.000x | — |
| ViTPose+ Small | 0.28 / 0.695x, unreliable boundary | 0.2037 | 1.57 / 0.990x | 0.3415 |
| MoveNet Lightning | 0.29 / 0.680x, unreliable boundary | 0.2215 | insufficient evidence | — |
| MoveNet Thunder | 0.07 / 0.830x | 0.0788 | insufficient evidence | — |
| BlazePose | 0 / 0.725x | 0.3250 | 1.34 / 1.045x | 0.2682 |
| HRNet-W32 | 0.30 / 0.705x | 0.1864 | 1.57 / 0.990x | 0.3415 |

ViTPose and HRNet supply more usable torso-feature frames in choreography
(A 69/69; B 81/87 and 80/87) than this MoveNet pipeline (A 46/69 and 45/69).
That is availability, not measured joint accuracy. At source 0.5s in Airflare B,
the preview visibly shows Lightning misplacing the raised leg while Thunder,
ViTPose and HRNet cover it more plausibly. This is a visual spot check, not an
exhaustive accuracy or identity audit.

**Subject contamination found in review:** choreography B at source 1.5s
(inside the selected interval) shows BlazePose on the foreground brown-pants
person, while ViTPose/HRNet follow the intended blue-gray-pants person at left.
MoveNet outputs combine foreground features with the subject/overlap region.
At 3s all five outputs are on the intended person. Thus the BlazePose alignment
number above is contaminated by changing identity, NOT an acceptable improvement
over the other models. MoveNet's rejected searches also have cross-person pose
contamination. Choreography A at 0.5s shows MoveNet attaching upper-body joints
to a background dancer. Screenshots at 0.5/1.5/3/5s support spot review; no full
ground-truth ID-switch count is claimed. Affected alignment-video sections carry
an explicit identity-mixing warning. These are manual observations on the pinned
fixtures and must be re-reviewed if the model, video or tracker changes.

### Interpretation

- **BlazePose is the speed-oriented candidate** in this desktop pipeline, with
  its own inexpensive detector. It has fewer usable feature frames, visibly
  changes subject in choreography B, and does not reproduce the manual timing;
  speed alone does not justify replacement.
- **MoveNet Thunder + rotations is worth further Airflare investigation**:
  0.83x is closer to 0.9x than the other newly added rot4 approaches here.
  Its choreography search fails, so it is not a general solution. Four-pass
  Airflare pipeline medians are about 618 / 722 ms per source frame A/B.
- **ViTPose/HRNet improve available pose evidence but not the systematic
  choreography start bias**. Both yield 0.99x but +0.37s start error.
- More/larger models or rotations are not sufficient for this alignment loss.
  Several rot4 runs have better feature coverage but worse timing than raw.
  No model reproduces both complete manual references. Keep these results as
  experiments; do not automatically replace the app's RTMPose-S pipeline.
- A next experiment should hold subject tracks fixed, assess phase/event
  correspondences and left/right ambiguities, then evaluate on additional
  held-out clips. Two references cannot establish a generally best model.

## Reproduction

Use the isolated `build/manual-pose-env` environment with numpy, OpenCV,
onnxruntime, scipy, transformers 4.49.0, and ffmpeg on PATH.

```powershell
build/manual-pose-env/Scripts/python.exe tools/download_expanded_pose.py
build/manual-pose-env/Scripts/python.exe tools/download_diverse_pose.py
build/manual-pose-env/Scripts/python.exe tools/test_diverse_pose_adapters.py
build/manual-pose-env/Scripts/python.exe tools/test_manual_alignment.py
build/manual-pose-env/Scripts/python.exe tools/benchmark_expanded_pose.py
build/manual-pose-env/Scripts/python.exe tools/render_expanded_pose.py --group standard
build/manual-pose-env/Scripts/python.exe tools/render_expanded_pose.py --group diverse
build/manual-pose-env/Scripts/python.exe tools/summarize_expanded_pose.py
build/manual-pose-env/Scripts/python.exe tools/verify_expanded_pose.py
```

`--models name ...` benchmarks a subset, preserving other models' results.
Caches fingerprint the input video, model, code and case configuration. A full
fresh run may invalidate earlier caches after adapter-code changes.

## Artifacts

`build/pose-expanded/index.html` is the review entry point, `measurements.csv`
is the complete timing/alignment table. `report.json` contains the numerical measurements and
alignment proposals; `*-selected.json` contains selected per-frame poses.

Skeleton grids are half-speed, 24fps display with 12fps inference samples, no
audio. They preserve source aspect ratio. `standard-models` shows the original
ten variants; `diverse-models` shows ViTPose, both MoveNets, BlazePose and HRNet.
Rendering decodes each source once into a panel-sized frame cache; it retains
original-coordinate geometry for overlays. This does not change benchmark
results, inference samples or alignment proposals.

Alignment comparison videos give each model a labelled section with MANUAL A/B
beside PREDICT A/B; an invalid search has a blank `NO VALID ALIGNMENT` panel.
