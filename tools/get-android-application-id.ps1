$ErrorActionPreference = 'Stop'
$gradleFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'android/app/build.gradle.kts'
$match = [regex]::Match((Get-Content -LiteralPath $gradleFile -Raw), '(?m)^\s*applicationId\s*=\s*"([A-Za-z][A-Za-z0-9_.]+)"\s*$')
if (-not $match.Success) { throw 'Cannot find Android applicationId in app/build.gradle.kts' }
$match.Groups[1].Value
