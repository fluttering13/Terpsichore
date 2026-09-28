# 支持作者

首頁的「支持作者」提供三個可設定管道，中英文皆支援：

- Google Play：一次性、非消耗型數位商品，各自定價及恢復。
  - 舞動之星紀念徽章：收藏於支持頁。
  - 晨曦金綠主題：變更 Material 控制元件與導覽配色；首頁品牌圖、影片和各功能既有語意色不變。購買／恢復後套用，可在支持頁切回原色。切換偏好目前僅保留於本次 App 執行期間。
- 綠界 ECPay：外部瀏覽器開啟作者收款連結，無數位回饋。
- Buy Me a Coffee：外部瀏覽器開啟作者支持頁，無數位回饋。

外部付款不會發放 Google Play 商品，不以返回 App 或成功開啟網頁作為付款成功證明。不設定網址時按鈕停用；沒有商品 ID／商店查無商品時不開放購買，不顯示虛構價格。

## 設定與定價

複製 `config/support.example.json`，填入自己的公開網址與 Play Console 商品 ID。此檔不需要金流密鑰；不要把服務帳戶或私密金鑰放進 App。

```powershell
flutter build appbundle --dart-define-from-file=config/support.example.json
```

在 Play Console 建立兩個不同 ID 的一次性商品，設定可購買選項及各地價格並啟用。例如可規劃徽章 NT$90、主題 NT$150，實際金額完全由 Console 決定。程式從 `ProductDetails.price` 顯示當地貨幣與格式；調整售價不用修改 App 的金額常數。一次購買即可持有，不能當作可重複購買的打賞。

`SUPPORT_DISTRIBUTION=play`（預設，未知值也視為 play）顯示 Google Play 商品；`direct` 用於自行發行 APK，顯示兩個外部管道。可在本機預覽三管道時，設定 `SUPPORT_PLAY_ECPAY_ALLOWED` 與 `SUPPORT_PLAY_COFFEE_ALLOWED` 為 true。

## Google Play 外部連結

Google Play 發行版預設隱藏外部入口。**開關僅控制 UI，並不建立政策資格。** 只有在具體收款安排符合純打賞例外，或完成適用地區的外部付款方案要求後，才能在相應發行範圍啟用。不能用語言選項判斷使用者適用地區；目前沒有地區資格判斷或替代付款方案 SDK，不應把開关用作這些方案的替代品。

Google 的純打賞例外要求款項 100% 給創作者且無數位內容／服務回饋。作者本人收款、金流扣費與 Buy Me a Coffee 平台費的具體安排尚未確認適用性，因此本專案不預設符合。

- https://support.google.com/googleplay/android-developer/answer/9858738
- https://support.google.com/googleplay/android-developer/answer/10281818

## 付款生命週期與驗證範圍

App 啟動建立長期購買監聽；離開支持頁仍會接收結果。等待付款、取消與錯誤不發商品；成功／恢復按商品 ID 發放對應小物，並完成 Play acknowledgement。啟動與「恢復購買」會查詢既有非消耗型商品；不使用本機偏好作為購買證明。失敗的 acknowledgement 保留給後續恢復重試。

目前使用官方 Flutter `in_app_purchase` 的裝置端購買結果，尚無後端 purchase token 驗證、即時退款撤權或跨平台帳戶同步。適用範圍限這兩項裝飾小物；若要增加付費功能或更強的防偽／退款同步，應接上 Google Play Developer API 驗證與 RTDN。商品恢復需要 Play 可用及相同 Google Play 帳號；此版本沒有離線持有快取。

尚未提供正式商品 ID、作者收款網址或測試帳戶。上架前需完成 Console 商品與付款資料設定，透過 Play 內部測試及 license tester 實測兩商品各自價格、購買、取消、延遲付款、重裝恢復、重複購買阻擋與 acknowledgement；外部網址需實測開啟及收款方身分。自動測試的 fake billing 不代表實際扣款已驗證。
