# Package SideLoador-Android for Windows with host adb/scrcpy (no bundling).
# Run in PowerShell on a Windows machine with Flutter + adb + scrcpy.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build_host_tools.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host "== flutter build windows --release =="
flutter build windows --release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Out = Join-Path $Root "build\windows\x64\runner\Release"
if (-not (Test-Path $Out)) {
  $Out = Get-ChildItem -Path (Join-Path $Root "build\windows") -Directory -Recurse |
    Where-Object { $_.Name -eq "Release" } | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Out -or -not (Test-Path $Out)) {
  Write-Error "Windows Release output not found"
  exit 1
}

# Host mode: remove any bundled tools leftover
$Tools = Join-Path $Out "tools"
if (Test-Path $Tools) { Remove-Item -Recurse -Force $Tools }

Write-Host "== Mode: HOST (uses system adb/scrcpy) =="
Write-Host "adb   = $((Get-Command adb -ErrorAction SilentlyContinue).Source)"
Write-Host "scrcpy= $((Get-Command scrcpy -ErrorAction SilentlyContinue).Source)"
Write-Host "Output: $Out"
Write-Host "Done."
