param(
    [Parameter(Mandatory=$true)][string]$Serial,
    [switch]$CheckSamsungDrawer
)
$ErrorActionPreference = 'Stop'
$package = 'com.example.terpsichore'
function Invoke-Adb {
    $result = & adb -s $Serial @args
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $args" }
    return $result
}
$entries = Invoke-Adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p $package
$aliases = @($entries | Where-Object { $_ -match 'com\.example\.terpsichore/' })
if ($aliases.Count -ne 1) { throw "Expected one enabled launcher: $entries" }
Write-Output "PASS PackageManager: $($aliases[0].Trim())"

if ($CheckSamsungDrawer) {
    # Read every page. Never restart/clear launcher caches: that would mask regressions.
    Invoke-Adb shell input keyevent KEYCODE_HOME | Out-Null
    Start-Sleep -Milliseconds 700
    Invoke-Adb shell input swipe 540 1800 540 500 300 | Out-Null
    Start-Sleep -Milliseconds 700
    function Read-Ui {
        Invoke-Adb shell uiautomator dump /sdcard/terpsichore-launcher-test.xml | Out-Null
        [xml]$xml = (Invoke-Adb shell cat /sdcard/terpsichore-launcher-test.xml) -join "`n"
        return $xml
    }
    $ui = Read-Ui
    if (-not $ui.SelectSingleNode('//node[@package="com.sec.android.app.launcher"]')) {
        throw 'Unlock the phone and leave Samsung One UI Home available.'
    }
    $pagePattern = '\u7b2c \d+ \u9801'
    $pages = @($ui.SelectNodes('//node') | Where-Object { $_.'content-desc' -match "$pagePattern\uff0c\u5171 \d+ \u9801" })
    if ($pages.Count -eq 0) { throw 'Samsung Traditional Chinese page indicators not found; UI check NOT passed.' }
    $count = 0
    foreach ($page in $pages) {
        if ($page.bounds -notmatch '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') { throw 'Invalid page bounds' }
        $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2)
        $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
        Invoke-Adb shell input tap $x $y | Out-Null
        Start-Sleep -Milliseconds 500
        $ui = Read-Ui
        $selected = $ui.SelectNodes('//node') | Where-Object { $_.'content-desc' -match '^\u5df2\u9078\u64c7, ' }
        $expectedPage = [regex]::Match($page.'content-desc', $pagePattern).Value
        if (-not ($selected.'content-desc' -match ([regex]::Escape($expectedPage) + '[,\uff0c]'))) {
            throw "Could not verify navigation to $expectedPage"
        }
        $count += @($ui.SelectNodes('//node[@text="Terpsichore"]')).Count
    }
    if ($count -ne 1) { throw "Samsung app drawer has $count Terpsichore items; expected one." }
    Write-Output "PASS Samsung drawer: one item across $($pages.Count) pages"
}
