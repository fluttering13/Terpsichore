param([Parameter(Mandatory=$true)][string]$Serial, [switch]$CheckSamsungDrawer)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
try {
    $info = & adb -s $Serial shell dumpsys package com.example.terpsichore
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
    $initial = & adb -s $Serial shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.example.terpsichore
    & flutter run -d $Serial --no-pub --no-resident
    if ($LASTEXITCODE -ne 0) { throw 'flutter run failed' }
    & "$PSScriptRoot/test-launcher-device.ps1" -Serial $Serial -CheckSamsungDrawer:$CheckSamsungDrawer
    $before = & adb -s $Serial shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.example.terpsichore
    if (($initial -join "`n") -ne ($before -join "`n")) { throw 'flutter run reset the selected icon' }
    & flutter build apk --debug --no-pub "--build-number=$($version + 1)"
    if ($LASTEXITCODE -ne 0) { throw 'Upgrade build failed' }
    & adb -s $Serial install -r build/app/outputs/flutter-apk/app-debug.apk
    if ($LASTEXITCODE -ne 0) { throw 'Upgrade install failed' }
    Start-Sleep -Seconds 2
    $updatedInfo = & adb -s $Serial shell dumpsys package com.example.terpsichore
    $updatedVersion = [regex]::Match(($updatedInfo -join "`n"), 'versionCode=(\d+)').Groups[1].Value
    if ([int]$updatedVersion -ne $version + 1) { throw 'Installed version did not increase' }
    $after = & adb -s $Serial shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.example.terpsichore
    if (($before -join "`n") -ne ($after -join "`n")) { throw 'Upgrade reset the selected icon' }
    & "$PSScriptRoot/test-launcher-device.ps1" -Serial $Serial -CheckSamsungDrawer:$CheckSamsungDrawer
    Write-Output "PASS flutter run reinstall and version $version -> $($version + 1) upgrade"
} finally { Pop-Location }
# Intentionally leaves the higher debug version installed; never uninstall or
# clear user data. On a personal phone restore with a debug APK and adb install -r -d.
