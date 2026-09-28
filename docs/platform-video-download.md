# 平台影片下載

首頁第五個功能及底部「平台下載」頁提供：貼上／解析連結、存取錯誤提示、選擇來源畫質、下載／合併影音、取消與本機儲存結果。中英文介面都支援。

## 行為

- 僅在使用者按「貼上連結」時讀剪貼簿；貼上後解析，仍須按「下載到本機」才下載。
- 支援 YouTube（含 Shorts）、Instagram Reels／影片貼文／單則限動、Facebook 影片／Reels／分享連結、Threads 影片貼文。
- 先取得影片中繼資料和真實格式。變更連結會清除前一支影片的選項，下載只能選擇本次解析取得的格式 ID。
- 不提供不存在的 1080p／4K 選項，也不放大低解析度來源。未知解析度明確標示，不拿貼文原圖尺寸代替影片尺寸。
- 同一解析度可能有不同位元率、FPS、編碼版本；格式 ID 保留在內部，介面顯示解析度、FPS、位元率、容器與估計大小。分離音軌自動合併成 MP4 或 MKV，不重新編碼影像；來源無音軌則明確標示。
- 多影片貼文會列出可下載影片的縮圖與頁數，預設全選，可單選、多選或全選，並各自選畫質。可分別下載，或依貼文順序合成一支影片。尚不支援帳號首頁或進行中的直播。
- 分別下載保留各支格式；合成逐支重新編碼為第一支的畫面比例、最高 1080p／30 fps，必要時留黑邊，統一 H.264 與 AAC 48 kHz 雙聲道。未取得音軌的片段補靜音並提示，不會假裝已取得 IG 額外配樂。
- 批次下載以整體進度顯示目前第幾支及下載／音軌合併／檢查／合成／儲存階段。個別失敗會列出頁數與原因，已儲存檔案保留；任何選取片段失敗都不輸出缺頁的合成檔案。可重新勾選失敗頁數重試。
- Android 10+ 用 MediaStore Downloads 寫入 `Download/Terpsichore`，不需整個儲存空間存取權。Android 7–9 存在 App 外部專用 Downloads 目錄並顯示完整位置；該目錄會隨解除安裝移除。
- 同時一項工作；可取消解析或下載。解析上限 2 分鐘、下載上限 30 分鐘，網路請求有 timeout 與有限重試。暫存檔於成功／失敗／取消後清除；MediaStore 失敗時移除未完成項目。
- App 被系統終止後不自動續傳；下載期間需保持 App 開啟。iOS/Web/桌面介面會提示目前僅支援 Android。

## 權限與失敗提示

解析到 private、needs_auth、premium_only、subscriber_only 或登入／年齡／401／403 問題時，以 `ACCESS_RESTRICTED` 提示，解析失敗時不提供下載按鈕。無法辨識的擷取失敗不直接斷言影片是私人，而提示權限或平台格式變動的可能。

另外區分 DRM、限流、已移除／地區限制、網路逾時、本機儲存權限、空間不足、無影片、取消、資訊過期。來源 CDN 也可能在解析成功後拒絕下載，該階段仍會顯示錯誤。

### Instagram 限動與登入

- 接受 `https://www.instagram.com/stories/<username>/<story-id>/` 單則限動連結；不接受整個帳號的限動集合或精選集合。
- 缺少登入狀態時，先顯示登入／匯入選項。登入開啟 App 內 Instagram HTTPS 網頁，使用者自行完成登入與驗證後按「登入完成」；不讀取密碼欄位，也不注入 JavaScript bridge。若 WebView 被平台拒絕，可改用匯入。
- 匯入限 1 MiB 內的 Netscape cookies.txt，只保留 Instagram 網域且未過期的 cookies，必須包含有效格式的 sessionid。這只是本機格式檢查；是否仍獲 IG 接受要在解析時確認。
- 登入資料以 Android Keystore AES-GCM 加密，存在 noBackup 私有目錄；每個 IG 解析／下載工作才產生短暫 cookie 檔，結束時刪除。不提供給其他平台、不上傳額外後端、不寫入日誌。清除登入狀態也清除 App WebView cookies 與目前預覽。
- 成功解析仍需使用者確認「下載到本機」，登入不會自動下載。
- 登入失效、額外驗證、限動失效、存取拒絕分開提示；拒絕存取時跳出通知並保留錯誤卡片。IG 若無法提供確切原因，提示可能尚未獲准追蹤、未在摯友名單、登入失效或限動不可用，不假裝知道對方好友設定。
- IG 的驗證及平台變動仍可能阻止下載；不繞過驗證或存取限制。此版本的真實帳號登入與私有限動下載仍需在裝置上手動驗證。

## 實作與更新

- Dart core：`lib/core/platform_download/platform_video.dart`
- Android bridge：`lib/infrastructure/platform_download/native_platform_video_downloader.dart`
- 原生引擎：`PlatformVideoDownloadPlugin.kt`，背景 worker + MethodChannel/EventChannel。
- [youtubedl-android](https://github.com/yausername/youtubedl-android) `0.18.1` 提供 Python 3.12、QuickJS、FFmpeg。
- APK 另附 [yt-dlp 2026.08.19](https://github.com/yt-dlp/yt-dlp/releases/tag/2026.08.19) 官方 standalone zip，取代 wrapper 內較舊的版本；含 EJS。SHA256、來源與授權在 `android/app/src/main/assets/platform_downloader/SOURCES.txt`。更新時需重驗官方 checksum、四平台樣本與 Android smoke test。
- Threads 使用 [tribixbite/yt-dlp-threads](https://github.com/tribixbite/yt-dlp-threads) 固定 commit 的 Unlicense extractor，修改為無法辨認目標貼文時拒絕下載，不選頁面推薦的無關影片；移除用原始尺寸猜測分流尺寸的行為。
- 不把 signed CDN URLs 或完整 extractor log 顯示到 UI／一般日誌。短期解析資料只保留在記憶體與本次工作的 cache JSON。
- 平台解析直接由裝置連線來源網站，無額外後端。平台變動、地區、網路及反機器人限制仍可能使個別公開影片失敗。

## 驗證

2026-09-23：以使用者提供的 `DdPF1dQk6yT` 貼文成功解析 9 支影片，Android 模擬器實測勾選第 2、7 頁，分別下載及合成皆成功，測試檔案已清除。另以有聲橫式／無聲直式測試片驗證合成順序、尺寸、黑邊、總時長及音軌。未登入時這則貼文的 9 支影片皆回報未取得音軌，下載第 1 頁 MP4 後以 ffprobe 確認實際只有影像；不能將 IG 播放時的聲音視為已保留。

```powershell
flutter test test/core/platform_video_test.dart test/widgets/platform_video_download_test.dart test/widget_test.dart test/widgets/home_logo_test.dart
flutter analyze
python tools/test_platform_threads.py
cd android
.\gradlew.bat :app:testDebugUnitTest :app:assembleDebug :app:assembleDebugAndroidTest -Ptarget-platform=android-x64
```

`PlatformDownloadSmokeTest` 是選擇性網路測試。安裝 debug APK 與 androidTest APK 到測試模擬器後執行（以實際 serial 取代 `emulator-5560`）：

```powershell
adb -s emulator-5560 shell am instrument -w -r -e class com.fluttering13.terpsichore.PlatformDownloadSmokeTest -e platformDownloadSmoke true -e videoUrl https://www.youtube.com/watch?v=jNQXAC9IVRw -e maxHeight 360 com.fluttering13.terpsichore.test/androidx.test.runner.AndroidJUnitRunner
```

會經過真正 Android plugin 解析、下載、合併與 MediaStore 寫入，驗證影片及音軌，最後刪除自己建立的測試下載。沒有指定 `platformDownloadSmoke=true` 時跳過，日常離線測試不連外。

2026-09-21 桌面執行 APK 所附相同 yt-dlp bundle 驗證使用者提供四個公開連結，皆完成下載並以 ffprobe 確認影像與音軌：YouTube 640×360（931 秒，可選至 3840×2160）、Instagram 1080×1920（32.9 秒）、Facebook 1440×2560（14.6 秒）、Threads 884×658（63.9 秒）。桌面測試不能取代 Android 原生儲存及裝置架構驗證。

同日再於 Android API 36 x86_64 模擬器，使用上述四個連結各自通過 `PlatformDownloadSmokeTest`：Threads 97.1 秒、Instagram 5.6 秒、Facebook 11.8 秒、YouTube 200.4 秒。四者皆經過真實 plugin、影音合併、MediaStore Downloads 儲存，並成功以 MediaMetadataRetriever 讀回影片尺寸及音軌。網路 smoke test 用較低解析度縮短下載時間；最高畫質清單另由解析結果確認。測試檔皆由測試程式刪除。ARM64 debug APK 已建置，尚未於實體 ARM64 手機驗證。
