# Platform setup

Run `flutter create --platforms=android,ios .` first to generate the native host
projects.

## iOS

Add these keys to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>顯示鏡像畫面，協助你練習舞蹈動作。</string>
<key>NSMicrophoneUsageDescription</key>
<string>錄製你的舞蹈練習影片。</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>選擇要練習或比較的舞蹈影片。</string>
```

Set the iOS deployment target to 16.0 or newer. This is required by the selected
ONNX Runtime plugin.

## Android

Add these permissions to `android/app/src/main/AndroidManifest.xml` above the
`application` element:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

Set `minSdk` to 24 or newer. File selection uses Android's system picker and does
not require broad storage permission. The Internet permission is used only to
download the HTDemucs model on first use. Keep `android:largeHeap="true"` on the
application because HTDemucs 6s needs about 1.1 GB while separating audio.
