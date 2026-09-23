# 介面語言

App 沿用設定中的繁體中文／English 選擇。Material 日期、時間及系統風格控制項使用對應的 `zh_TW`／`en` locale。

學習模式、音樂分軌與循環、A/B 分析與 AI 設定、自訂音源、匯出預覽、影片轉檔、專案管理、相機及倍速控制項的文字，集中於 `lib/entrypoints/mobile/localization/english_messages.dart`。首頁、平台下载與通知設定已有的雙語文案仍使用原有選擇方式。

`appText(context, 中文模板, [參數])` 依語言選擇模板，並訂閱 locale 變更。`{0}`、`{1}` 等參數一次替換，檔名、專案名稱與使用者輸入不會被當成翻譯文字或再次替換。

`english_errors.dart` 翻譯 App 自行定義的處理錯誤；第三方工具或裝置回傳的原始診斷保留原文。核心處理層不依賴 Flutter 的語言狀態。

彩蛋的中英文資料集中於 `easter_egg_catalog.dart`，兩份 catalog 的 ID 必須一致。`egg.md` 保留繁體中文彩蛋規格。

驗證：`flutter test test/widgets/localization_test.dart` 包含翻譯完整性、參數一致性、語言切換、彩蛋提示、專案名稱保留，以及窄螢幕英文排版測試。
