# A+B multi-person filtering switch

AI settings now includes `多人篩選邏輯`, default ON for existing/missing preferences, saved as boolean `multiPersonFiltering` in pose_settings.json. Cancel does not apply changes. Changing it invalidates both raw and smoothed pose caches without altering trims/rates. FPS and smoothing remain independent.

ON: current core-gated/grace subject tracking and direction retries. UI describes previous shoulder/hip core continuity, not guaranteed identity recognition or a user-selected person.

OFF: fixed full-image ROI, rotation0, exactly one inference per selected sample; no subject-dependent crop, same-subject rejection, core checks, direction retry, whole-frame confidence rejection, or temporal repair. Retain normal decode/resize/color-format/tensor preprocessing and coordinate restoration. Per-point model confidence retained. Adaptive/fixed FPS settings still apply. Median smoothing (if enabled) and alignment search unchanged; preview still hides low-confidence joints as before.

This is stricter raw mode than the historical `directionRetries:false` experiment, which still used subject crops and continuity rejection. Historical no-retry times do not directly benchmark this new mode.

Widget regression covers default ON, toggling OFF and cancellation returning to ON. Native harness `--dart-define=POSE_MULTI_PERSON=false` asserts calls equal sampled frames, but that new native run has not yet been executed. Full81-test suite passed before wording-only updates; analyze clean. No fresh performance claim for this toggle.
