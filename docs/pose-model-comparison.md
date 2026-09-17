# 倒立影片模型比較：2026-09-17

## 結論

本輪建議把 **RTMPose-S 列為下一階段主候選，YOLO11s-Pose 列為較簡單的單階段備選**，不是宣布已找到可直接上線的最佳模型。

RTMPose-S 在抽查倒立影格的身體結構較合理，A 加旋轉補救後有改善；但 B 上目前的旋轉選擇、追蹤和平滑也會使結果變差。下一步應做「指定主角 + 選擇性旋轉補救」，而非直接上線本次四方向後處理。

LitePose 最快，但漏點及誤抓背景人物明顯。WholeBody 在本次只比較身體 17 點的工作上，沒有顯示足以抵銷額外成本的明顯優勢；沒有評測手指、臉部與腳部細節，不能因此認定它的全身辨識能力較差。

## 素材與方法

- A：Download 中指定的 `SaveClip.App_…G9-U_1.mp4`，約 1.37 秒；B：`DCIM/Camera/20260915_213728_1.mp4`，約 3.68 秒。
- 原檔未修改、未上傳，僅複製至本機忽略版控的 build 目錄。以 6 fps 抽取 A 8 幀、B 22 幀；這不是逐原始影格 30 fps 全量評測。
- 四個候選：既有 LitePose、YOLO11s-Pose、RTMPose-S、RTMPose-M WholeBody。這裡的「全部」指這四個實驗候選，不代表測遍所有姿態模型。
- baseline：僅必要前處理與模型解碼。YOLO 保留偵測 NMS，LitePose 保留熱圖候選點／AE 分組，不加 App 的多人整幀拒絕與 8 點整幀拒絕。顯示門檻统一 0.3，但不同模型分數並未校準，不可視為相同可信度。
- RTMPose 是 top-down 模型，兩輪都用 YOLO11s-Pose 提供人框；初始取最大人物框，因此與單模型相比是完整 pipeline 比較，不是使用人工真值框。
- post：每幀跑 0/90/180/270 度，將座標轉回原畫面；同模型內以身體關節平均分數及前幀框 IoU 選擇結果。可用關節以 80% 現幀 + 20% 前幀平滑，不填補缺失關節。
- 四方向推論是 test-time augmentation，嚴格來說不只是輸出後處理；時間已包括額外推論，不隱藏其成本。
- 沒有人工真值關節、PCK/OKS 或身分標註；效果結論來自對照圖的目視檢查，不能當成量化準確率或通用排名。

## 時間：電腦 CPU，不是手機

Windows 11、Intel Core i9-14900F、ONNX Runtime 1.20.1 CPUExecutionProvider，intra-op 2 / inter-op 1，每個模型先暖機 3 次。下表為 A+B 共 30 幀的中位數，單位 ms/幀，單次實驗，不含重複實驗信賴區間。

| Pipeline | baseline 推論 | baseline 完整 | post 推論 | post 完整 |
| --- | ---: | ---: | ---: | ---: |
| LitePose | 44.1 | 45.1 | 177.5 | 200.5 |
| YOLO11s-Pose | 93.1 | 96.1 | 373.3 | 404.2 |
| YOLO11s + RTMPose-S | 100.0 | 103.8 | 399.9 | 433.8 |
| YOLO11s + RTMPose-M WholeBody | 112.4 | 116.2 | 449.0 | 483.5 |

「推論」為該 pipeline 所有 ONNX session.run 的累計時間，RTMPose 包括人框偵測器；「完整」再包含旋轉、resize、正規化、解碼、人物選擇和平滑。不包含讀取／解碼影片、模型載入、繪圖、Flutter channel 或 UI。各 clip 的 p95 及每幀資料見 `build/pose-candidates/report.json`。

## 效果與失敗案例

| Pipeline | baseline | 本次 post |
| --- | --- | --- |
| LitePose | A 多數倒立影格沒有完整身體；B 會抓背景 | 救回部分翻轉姿態，B 結尾仍抓錯人 |
| YOLO11s-Pose | 常有很多點，但 A 約 0.67/0.83 秒的肢體結構不合理 | 部分影格改善，但不能靠分數保證選中正確方向，B 結尾跳到背景 |
| RTMPose-S | 可抓出部分倒立結構，A 有缺肢，B 部分倒立比 YOLO 更合理 | A 完整度改善；B 約 1.67 秒出現錯誤交叉／位移，結尾追錯人 |
| RTMPose-M WholeBody | A 在固定顯示門檻下缺點較多 | A/B 部分倒立變完整，但仍有缺點與背景切換，額外成本較高 |

僅作診斷的「至少 8 個身體點 ≥0.3」幀數（不是準確率）：

| Pipeline | A baseline → post（共 8 幀） | B baseline → post（共 22 幀） |
| --- | ---: | ---: |
| LitePose | 0 → 2 | 8 → 14 |
| YOLO11s-Pose | 8 → 8 | 20 → 22 |
| RTMPose-S | 5 → 8 | 11 → 16 |
| RTMPose-M WholeBody | 0 → 6 | 5 → 16 |

YOLO 點數最多不等於最好，尤其 B post 3.50 秒抓到背景人物。快動作的固定平滑亦可能拖後，因此不應把本次 post 當成預設改善。

## 重現與輸出

在隔離 Python 環境安裝 numpy、opencv-python、onnxruntime，執行：

```powershell
python tools/download_pose_candidates.py
python tools/benchmark_pose_candidates.py build/pose-user-a.mp4 build/pose-user-b.mp4
python tools/render_pose_benchmark.py build/pose-user-a.mp4 build/pose-user-b.mp4
```

輸出於 `build/pose-candidates/`：

- `A-comparison.mp4`、`B-comparison.mp4`：上排 baseline、下排 post；左至右 LitePose、YOLO、RTMPose-S、WholeBody。6 fps 抽樣重播，未補幀、無音訊。
- `{A,B}-{model}.jpg`：每個模型的五個等間隔抽查畫面，上排 baseline、下排 post。
- `report.json`：模型大小、載入時間、環境、每幀輸出關節及耗時。

模型都留在 build，未新增到 App、未替換手機模型，也未改動原本 A 最短 2 秒的限制。尚未測這些候選的 Android 載入、效能或 A/B 最終對齊誤差。

## 來源

- [YOLO11 官方模型說明](https://huggingface.co/Ultralytics/YOLO11)，本輪使用 [AXERA ONNX 鏡像](https://huggingface.co/AXERA-TECH/YOLO11-Pose)，revision `156938308275ed3dbe3772898d8766a399aeb173`。
- [RTMPose 官方專案](https://github.com/open-mmlab/mmpose/tree/main/projects/rtmpose)、[官方 ONNXRuntime 前後處理範例](https://github.com/open-mmlab/mmpose/blob/main/projects/rtmpose/examples/onnxruntime/main.py)，本輪使用 [RTMPose ONNX 鏡像](https://huggingface.co/bukuroo/RTMPose-ONNX)，revision `a6e9fb8a9190efd0383b059033f45645180cc7df`。
- LitePose 來源見 `litepose-alignment.md`。下載腳本固定候選模型 revision 與 SHA-256；鏡像實際權重的完整訓練設定仍需上線前核對。
- 依需求暫不以授權篩掉候選，不代表已完成正式散布授權審核。
