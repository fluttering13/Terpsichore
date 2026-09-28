# Google Play 內部測試

套件名稱：`com.fluttering13.terpsichore`。本次版本為 `0.1.0+2`（versionCode 2）。

## 本機簽署與建置

Release 使用 upload key，不再使用 Android debug key。首次準備已在本機建立：

- `android/upload-keystore.jks`：上傳簽署私鑰，alias 為 `upload`。
- `android/key.properties`：密碼與 keystore 相對於 `android/` 的路徑。

兩者均由 `android/.gitignore` 排除。請將這兩個檔案一起備份至你控制的安全位置；不要加入 Git、貼到聊天或放進 App assets。重新 clone 專案後，需還原它們才能建置 signed release。日後使用相同 upload key 更新此 Play App；若已在 Console 登錄其他 upload key，應先核對／處理重設流程，不能直接換 key 更新。

```powershell
flutter build appbundle --release --dart-define-from-file=config/support.example.json
```

輸出：`build/app/outputs/bundle/release/app-release.aab`。

此設定目前沒有真實商品 ID、收款網址；內購顯示尚未開放，Google Play 版外部付款入口隱藏。此包可先測核心功能，不會提供真實付款。設定商品後需另外驗證 Play 內購。

2026-09-23：已產生本機 upload key 簽署的 AAB，約 334 MiB。`bundletool 1.18.3 validate` 通過，憑證主體為 `CN=Terpsichore Upload, OU=Development, O=fluttering13`。48 個直接封裝於 arm64-v8a／x86_64 的 ELF 函式庫通過 PT_LOAD 16 KB 對齊檢查；這不涵蓋壓縮 runtime 內所有執行檔或 16 KB 裝置實際執行驗證。尚未上傳 Play Console，也未從 Play 安裝實測。AAB 包含多種架構與符號，檔案大小不等於各裝置的 Play 壓縮下載大小。

每次重新上傳新版本時，增加 `pubspec.yaml` 的 `+` 後版本代碼（例如 `0.1.0+2`）；同一 versionCode 不要重複上傳不同 bundle。

## Release 啟動回歸檢查

2026-09-28：Play versionCode 1 在 Samsung SM-S9180 點開即閃退，紀錄為
`Unable to get provider androidx.startup.InitializationProvider` →
`Failed to create an instance of androidx.work.impl.WorkDatabase`。
同一 AAB 透過 bundletool 產生的 split APK 在 API 36 模擬器重現相同錯誤。
R8 的 `usage.txt` 確認移除了 `WorkDatabase_Impl` 的 `public void <init>()`；
Room 2.2.5 原本的規則只保留類別，未保留反射建立資料庫所需的建構函式。
versionCode 2 在 `android/app/proguard-rules.pro` 明確保留 RoomDatabase 子類別的無參數建構函式。

修正驗證：release AAB 建置與 bundletool validate 通過；同一 API 36 模擬器從 versionCode 1
更新到 2 後成功進入首頁，強制停止後透過 launcher alias 冷啟動也通過，crash buffer 無錯誤。
R8 seeds 確認建構函式保留。測試用 split APK 由 bundletool 以本機 debug key 簽署，
內容仍為該 release AAB。尚待 Play 更新後於原手機驗證。
本次 AAB SHA-256：`35C6D85F326A6366EFD5EBE7E98A533F641ACA4450296A454C9EEB4A59955CEE`。

每次更動 release 最佳化或 Android 相依套件後：

1. 建置 release AAB，確認 `build/app/outputs/mapping/release/seeds.txt` 包含
   `androidx.work.impl.WorkDatabase_Impl: WorkDatabase_Impl()`。
2. 使用 `bundletool build-apks` 將該 AAB 依測試裝置規格產生 split APK，安裝到測試模擬器，
   驗證首次啟動與強制停止後重新啟動，確認首頁出現且無此 App 的致命錯誤。
3. 上傳 Play 測試軌後，再用 Play 安裝／更新在實機驗證；本機簽章的 APK 無法保證可覆蓋 Play 版本，
   不要為測試直接移除使用者的 Play 安裝或清除資料。

已安裝 release 的測試模擬器可執行：

```powershell
python tools/test_release_startup.py --serial emulator-5554
```

也可加上 `--apk <release.apk>` 安裝相同簽章的 release APK。腳本拒絕實機及 debuggable
版本，連續驗證兩次 launcher 冷啟動、程序存活與首頁畫面；證據保存在 `build/release-startup/`。
CI 以 runner 的臨時 debug key 簽署經 R8 最佳化的 release，先執行此檢查再跑 debug 裝置測試。
此 CI 簽章僅供模擬器測試，不能上傳 Play。

[R8 full mode 文件](https://r8.googlesource.com/r8/+/refs/heads/main/compatibility-faq.md#r8-full-mode)
說明類別被保留不代表其預設建構函式也會保留。

## Play Console 操作

1. 開啟 Terpsichore App，確認帳戶驗證與 Console 提示的必要待辦。
2. 前往「測試與發布 → 測試 → 內部測試」。
3. 在「測試人員」建立 email 清單，加入自己及測試者使用 Google Play 的 Google 帳號並儲存。
4. 在「版本」建立新版本。首次依提示設定 Play App Signing；本機 upload key 用於簽署上傳檔，Google 管理的 app signing key 用於使用者安裝的 APK。
5. 上傳上述 `.aab`，確認套件名稱、版本代碼、支援裝置與 Console 檢查結果。填寫版本說明，檢查並推出至「內部測試」。
6. 複製加入測試連結。測試者以名單中的帳號開啟連結並加入，再透過 Google Play 安裝。AAB 本身不能直接點開安裝到手機。

第一次處理不保證立即可下載；以 Console 實際狀態為準。不要因為搜尋商店找不到，就認為測試版本發布失敗，應使用加入測試連結。

目前手機若已安裝同套件名稱的 debug APK，可能因為簽章不同無法直接更新到 Play 版本。先匯出需要的資料再移除 debug 版，或使用另一台測試裝置；解除安裝會移除 App 私有資料。舊 `com.example.terpsichore` 是不同套件，不會被新套件自動更新或搬移資料。

## 本輪測試內容

- 從 Play 安裝後啟動、語言切換、授權相機／麥克風／通知。
- 學習模式：匯入、播放、拖曳、循環、鏡頭預覽與錄影。
- A+B 分析：不同影片、短片段、對齊、預覽及匯出。
- 純音樂：模型首次下載、分軌、混音與循環。
- 影片轉檔、合法且有權下載之平台影片、實際儲存結果。
- 鎖屏、背景／恢復、低儲存空間、拒絕權限與弱網路。
- 支持作者：未設定管道不可付款；之後另用 license tester 測商品購買／恢復。

內部測試不取代新個人帳戶的封閉測試要求。未來申請正式發布仍需完成適用的 12 位測試者連續加入封閉測試 14 天，以及正式發布存取權審查。

官方參考：

- https://docs.flutter.dev/deployment/android
- https://support.google.com/googleplay/android-developer/answer/9845334?hl=zh-Hant
- https://support.google.com/googleplay/android-developer/answer/14151465?hl=zh-Hant
