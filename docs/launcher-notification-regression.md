# Launcher and daily-reminder regression

## Observed failure and fix

On SM-S9180 / Samsung One UI, the app drawer contained four Terpsichore
items despite one installed package and one enabled launcher component.
Two separately opened items resolved to the same `FlutterDebugLauncher`.
Restarting only One UI Home removed the cached duplicates; no launcher data
or home-screen layout was cleared. This proves a launcher-cache problem,
not four installed apps. It does not prove which historical event created
every cached item.

Keep component names stable, disable historical aliases, atomically normalize
aliases on Android 13+, and skip already-normalized writes. Builds must not
broadcast an icon reset to a connected phone. An update preserves the saved
emotion icon. Changes are deferred while MainActivity is alive to protect
file-picker return flows; finishing the activity applies the pending icon.
Simply pressing Home can leave an activity alive, so switching is not promised
to be immediate in that case.

Flutter reads the default launch target from APK metadata, not the installed
dynamic component state. The debug manifest gives MainActivity a MAIN/LAUNCHER
filter with a required `terpsichore-debug` URI. Flutter can explicitly start it,
but ordinary no-data launcher queries cannot match it. Release does not contain
this development-only filter. Do not add an unqualified LAUNCHER filter to
MainActivity or restore the old pre-build ADB reset.

The old reminder skipped days when the app had already been opened and opening
scheduled the next day. The new rule is daily at the configured local time
(default 18:00), including days already opened. Permission/channel settings can
still block delivery; exact alarm access is required for exact timing. A separate
10-second test alarm posts notification 7322 without advancing streaks or the
daily-delivery marker. Clock/time-zone changes and updates restore scheduling.

## Automated coverage

- Four JVM tests: before/at/after reminder time and daylight-saving transition.
- Three instrumentation tests against real Android PackageManager: eight
  consecutive opens on different dates with real streak-to-icon selection,
  same-day idempotence, deferred changes while host is alive, repeated update
  normalization, and repair of two enabled aliases. Test preferences are isolated;
  the original alias and real reminder schedule are restored afterward.
- `tools/test-launcher-upgrade.ps1`: real `flutter run -d` build/install/start,
  then a versionCode increment and `adb install -r`; assert the selected icon is
  preserved and there is exactly one enabled launcher after each operation.
- `tools/test-launcher-device.ps1 -CheckSamsungDrawer`: inspect all pages of
  the Traditional Chinese Samsung app drawer and require exactly one item.
  Missing UI, unexpected navigation, or duplicates fail rather than pass silently.
  It never restarts or clears the launcher to make an assertion pass.
- CI runs JVM tests, Android API 34 instrumentation, and reinstall/update
  regression. Samsung-specific cache validation remains a physical-device gate;
  an AOSP emulator cannot certify Samsung Home behavior.

Run from the repository root, with the device unlocked and not being operated:

```powershell
cd android
.\gradlew.bat :app:connectedDebugAndroidTest --console=plain
cd ..
powershell -ExecutionPolicy Bypass -File tools/test-launcher-upgrade.ps1 -Serial DEVICE_SERIAL -CheckSamsungDrawer
```

Use a matching debug installation (versionCode equals pubspec) before the upgrade
script. It intentionally leaves versionCode + 1 installed. To restore the normal
debug build without removing user data:

```powershell
flutter build apk --debug --no-pub
adb -s DEVICE_SERIAL install -r -d build/app/outputs/flutter-apk/app-debug.apk
```

Never uninstall or clear app/launcher data as part of this regression.
For production distribution, additionally test signed release-to-release
updates, pinned home-screen shortcuts, another OEM launcher, Android 12's
non-atomic fallback, a real 18:00 delivery, and reboot/permission scenarios.
These are not covered by the debug Samsung result or mocked host lifecycle.

## Device evidence (2026-09-17 / 18)

- Plain resident `flutter run -d R5CWC1Z5EJM --no-pub`: app started and Dart VM
  service attached with HappyIcon already active after the debug-entry fix.
- Instrumentation: `OK (3 tests)`; afterward exactly one item across all nine
  Samsung drawer pages, without resetting the launcher between assertions.
- Same-version overwrite and versionCode 1 to 2 update: preserved HappyIcon;
  exactly one enabled component and one item across all nine pages.
- The complete no-UI reinstall/upgrade script also passed. A later full drawer
  rerun correctly failed when the phone locked. After the user unlocked it,
  the final rerun passed: one enabled HappyIcon and one item across nine pages.
- Background 10-second alarm: NotificationManager recorded notification 7322.
  This is not a claim that a real scheduled 18:00 delivery has already occurred.

The GitHub workflow has been edited locally, not pushed or executed remotely.

## Default vibration (2026-09-18)

New notification channels enable system-default vibration and the app declares
VIBRATE. Android 7 uses DEFAULT_VIBRATE. Existing channel IDs are preserved:
Android does not let apps overwrite their vibration behavior after creation.
An existing installation must enable vibration in the channel's system settings;
do not delete/recreate channels or change their IDs to bypass user preferences.
On the test Samsung, the user-requested channel switch was enabled and Android
reported `mVibrationEnabled=true`. Sound volume and popup settings were unchanged.
