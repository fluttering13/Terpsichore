param(
    [Parameter(Mandatory=$true)][string]$Serial,
    [switch]$CheckSamsungDrawer,
    [switch]$PrepareEmulator
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$package = & "$PSScriptRoot/get-android-application-id.ps1"
Push-Location $repo
try {
    # connectedDebugAndroidTest can remove its app during cleanup. Restore the
    # debug APK and establish the dynamic icon before testing reinstall/upgrade.
    if ($PrepareEmulator) {
        if ($Serial -notmatch '^emulator-\d+$') { throw 'PrepareEmulator requires an emulator serial' }
        & adb -s $Serial install -r build/app/outputs/flutter-apk/app-debug.apk
        if ($LASTEXITCODE -ne 0) { throw 'Preparing emulator APK failed' }
        & adb -s $Serial shell am broadcast -n "$package/.DebugLauncherReceiver" -a "$package.TEST_ICON" --es alias HappyIcon
        if ($LASTEXITCODE -ne 0) { throw 'Preparing dynamic launcher icon failed' }
        & "$PSScriptRoot/test-launcher-device.ps1" -Serial $Serial
    }
    $info = & adb -s $Serial shell dumpsys package $package
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read installed package' }
    $match = [regex]::Match(($info -join "`n"), 'versionCode=(\d+)')
    if (-not $match.Success) { throw 'Install the debug app first' }
    $version = [int]$match.Groups[1].Value
    $pubspec = Get-Content pubspec.yaml -Raw
    $sourceVersion = [int][regex]::Match($pubspec, '(?m)^version:.*\+(\d+)').Groups[1].Value
    if ($version -ne $sourceVersion) {
        throw 'Installed version must match pubspec before this test. Restore a matching debug APK with adb install -r -d; never uninstall user data.'
    }
    # Real Flutter build/install/start, with the existing dynamic icon enabled.
    $initial = & adb -s $Serial shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p $package
    & flutter run -d $Serial --no-pub --no-resident
    if ($LASTEXITCODE -ne 0) { throw 'flutter run failed' }
    & "$PSScriptRoot/test-launcher-device.ps1" -Serial $Serial -CheckSamsungDrawer:$CheckSamsungDrawer
    $before = & adb -s $Serial shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p $package
    if (($initial -join "`n") -ne ($before -join "`n")) { throw 'flutter run reset the selected icon' }
    & flutter build apk --debug --no-pub "--build-number=$($version + 1)"
    if ($LASTEXITCODE -ne 0) { throw 'Upgrade build failed' }
    & adb -s $Serial install -r build/app/outputs/flutter-apk/app-debug.apk
    if ($LASTEXITCODE -ne 0) { throw 'Upgrade install failed' }
    Start-Sleep -Seconds 2
    $updatedInfo = & adb -s $Serial shell dumpsys package $package
    $updatedVersion = [regex]::Match(($updatedInfo -join "`n"), 'versionCode=(\d+)').Groups[1].Value
    if ([int]$updatedVersion -ne $version + 1) { throw 'Installed version did not increase' }
    $after = & adb -s $Serial shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p $package
    if (($before -join "`n") -ne ($after -join "`n")) { throw 'Upgrade reset the selected icon' }
    & "$PSScriptRoot/test-launcher-device.ps1" -Serial $Serial -CheckSamsungDrawer:$CheckSamsungDrawer
    Write-Output "PASS flutter run reinstall and version $version -> $($version + 1) upgrade"
} finally { Pop-Location }
# Intentionally leaves the higher debug version installed; never uninstall or
# clear user data. On a personal phone restore with a debug APK and adb install -r -d.
