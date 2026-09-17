# LitePose A+B 試用版

## 操作

- A、B 各自的骨架按鈕可分析、顯示或隱藏骨架，不必先執行對齊。
- 「AI 對齊（固定 A）」保留 A 的裁切、速度，只搜尋 B 的起點及固定播放速度。
- 結果先顯示建議，使用者確認「套用並預覽」才更動 B；可以復原。
- 骨架是預覽用，不會燒錄到匯出影片，也不會儲存到專案。

## 第一版限制

- LitePose-S COCO 17 關節，不含細部手指。適合單一主要舞者；多人的偵測與分組不是可靠的身分追蹤。
- 本機 CPU 推論、448 × 448 輸入，每秒抽 6 幀；不是即時攝影機推論。
- 對齊 A 限 2–30 秒，B 搜尋區間限 2–60 秒；單獨骨架分析限 2–60 秒。
- B 固定速度搜尋範圍 0.1–2 倍，必須在選取範圍內完整覆蓋 A 的有效播放時間。不做分段變速。
- 使用髖部中點作為身體中心的近似，並非物理質心；比較中心化、軀幹尺度正規化的身體關節相對向量。鏡像會連同左右關節配對處理。
- 粗搜後局部細搜，最小化可信度加權的姿勢差異；這是近似最佳解，不保證全域最小。
- 可用影格不足、姿勢幾乎不變或誤差過高時不套用。重複舞步仍可能有多個相近答案，需人工預覽確認。
- 信心分數及拒絕門檻是啟發式設定，尚未完成真實舞蹈資料集的準確率與手機效能評測。
- 分析快取只留在目前畫面的記憶體中；取消會等待目前推論／抽幀工作結束，再釋放模型與暫存檔。

## 模型來源與授權

- 上游：[mit-han-lab/litepose](https://github.com/mit-han-lab/litepose)，MIT。
- 模型鏡像：[cansik/visiongraph](https://huggingface.co/cansik/visiongraph)，見其 [MODEL_ATTRIBUTIONS.md](https://huggingface.co/cansik/visiongraph/blob/main/MODEL_ATTRIBUTIONS.md)。
- 固定鏡像 revision：`0de7ab36c9cf7d0843a1a19fd8c83db34a19d8a3`。
- 來源：`litepose-auto-s-coco-fp32.xml` / `.bin`；來源 SHA-256 固定於轉換腳本。
- 官方 Hugging Face 的 Nano tar 是 Jetson/CUDA 編譯產物，不能直接給 Android 使用，因此本版使用可轉換的 S 模型鏡像。
- 隨 App 包含 `asset/models/LITEPOSE_LICENSE.txt` 與約 11 MB ONNX 模型。
- ONNX SHA-256：`6911675e168e63cfef4653e92883f9a09c19dd0fee31503cd45658f3141205b4`。

## 轉換與驗證

`tools/export_litepose.py` 說明隔離 Python 環境所需套件，下載時驗證來源雜湊。轉換使用 ONNXifier，並比較 OpenVINO 與 ONNX 原始輸出，再加入熱圖融合、NMS、每關節前 5 個候選點及 tag 輸出。

輸入為 **BGR、float32、0–255、NCHW**。均值／尺度轉換已包含在模型內，不能再做一次 ImageNet 正規化。影片以維持比例、黑邊填補方式輸入；解碼回復原影片座標。

已完成：轉換數值一致性檢查、時間偏移／變速／鏡像／靜止與缺失姿勢／區間覆蓋／骨架插值／多人拒絕單元測試、Flutter analyze、全套 Flutter tests、Android debug APK 建置。

### 2026-09-17 實機冒煙測試

Samsung SM-S9180（debug APK）：發現並修正 `Directory.createTemp` 誤將不存在的子路徑當成父目錄，改由系統暫存目錄建立帶前綴的獨立工作目錄。

修正後完成模型載入、8 秒片段骨架分析、A/B 獨立顯示與隱藏。同一測試影片置於 A/B，建議為 B 起點 0.00 秒、1.000 倍、有效骨架 73%、差異 0.027；套用後播放至末尾，A 仍為 0–8 秒、1 倍。按復原後建議標籤移除且共同進度回到起點。檢查時 crash buffer 為空，分析工作目錄已清除。

素材是上游示範影片裁切，含原有骨架，不代表獨立準確率評測。仍需驗收：真實單人舞蹈品質、分析取消與重進畫面、實機已知偏移／變速影片、非預設參數的復原、長片段耗時與記憶體。
