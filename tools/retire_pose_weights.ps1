param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$retired = @('rtmpose-s.onnx', 'rtmpose-m.onnx', 'rtmpose-l.onnx', 'rtmpose-x.onnx',
  'rtmpose-m-wholebody.onnx', 'litepose_s_coco.onnx', 'yolov8n-pose.onnx',
  'yolov8s-pose.onnx', 'yolov8m-pose.onnx', 'vitpose-small.onnx', 'hrnet-w32.onnx',
  'movenet-lightning.onnx', 'blazepose.onnx', 'blazepose-detector.onnx')
$folders = @('asset/models', 'build/pose-candidates', 'build/unit_test_assets/asset/models',
  'build/app/intermediates/flutter/debug/flutter_assets/asset/models',
  'build/app/intermediates/assets/debug/mergeDebugAssets/flutter_assets/asset/models')
$targets = foreach ($relative in $folders) {
  $folder = Join-Path $projectRoot $relative
  if (Test-Path -LiteralPath $folder) {
    Get-ChildItem -LiteralPath $folder -File | Where-Object { $_.Name -in $retired }
  }
}
$audit = foreach ($file in $targets) {
  $resolved = (Resolve-Path -LiteralPath $file.FullName).ProviderPath
  if (-not $resolved.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Target outside project: $resolved"
  }
  if ($file.Name -notin $retired -or $file.Extension -ne '.onnx') { throw 'Invalid retirement target' }
  [PSCustomObject]@{ Path = $resolved; Bytes = $file.Length; SHA256 = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash }
}
$audit | Format-Table Path, Bytes -AutoSize
if (-not $Apply) { Write-Output 'Dry run only. Pass -Apply to move these exact files to Recycle Bin.'; exit }
# No directory deletion, no recursive moves, no user media/report removal.
Add-Type -AssemblyName Microsoft.VisualBasic
foreach ($item in $audit) {
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($item.Path,
    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
}
$audit | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $projectRoot 'build/retired-pose-weights.json') -Encoding utf8
Write-Output "Moved $($audit.Count) model files to Recycle Bin. Thunder and the YOLO11s detector are retained."
