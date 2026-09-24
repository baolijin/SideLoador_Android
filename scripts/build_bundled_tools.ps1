# Package SideLoador-Android for Windows with adb.exe + scrcpy.exe + DLLs bundled.
# Run in PowerShell on a Windows machine that has adb and scrcpy installed.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build_bundled_tools.ps1
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

# Resolve tools
$Adb = $env:ADB_PATH
if (-not $Adb) {
  $c = Get-Command adb -ErrorAction SilentlyContinue
  if ($c) { $Adb = $c.Source }
}
if (-not $Adb) {
  foreach ($p in @("C:\Android\platform-tools\adb.exe", "C:\Program Files\platform-tools\adb.exe")) {
    if (Test-Path $p) { $Adb = $p; break }
  }
}
$Scrcpy = $env:SCRCPY_PATH
if (-not $Scrcpy) {
  $c = Get-Command scrcpy -ErrorAction SilentlyContinue
  if ($c) { $Scrcpy = $c.Source }
}
if (-not $Scrcpy) {
  foreach ($p in @("C:\Program Files\scrcpy\scrcpy.exe", "C:\scrcpy\scrcpy.exe")) {
    if (Test-Path $p) { $Scrcpy = $p; break }
  }
}
if (-not $Adb -or -not (Test-Path $Adb)) { Write-Error "adb not found (set ADB_PATH)"; exit 1 }
if (-not $Scrcpy -or -not (Test-Path $Scrcpy)) { Write-Error "scrcpy not found (set SCRCPY_PATH)"; exit 1 }

$Tools = Join-Path $Out "tools"
if (Test-Path $Tools) { Remove-Item -Recurse -Force $Tools }
New-Item -ItemType Directory -Path $Tools -Force | Out-Null

Copy-Item $Adb (Join-Path $Tools "adb.exe") -Force
Copy-Item $Scrcpy (Join-Path $Tools "scrcpy.exe") -Force
Write-Host "Copied adb.exe + scrcpy.exe -> $Tools"

# Copy non-system DLLs next to scrcpy.exe (Windows loads from exe directory)
python - <<'PY' $Tools $Scrcpy
import os, sys, subprocess, shutil, re
from collections import deque

tools, scrcpy = sys.argv[1], sys.argv[2]
SYSTEM_HINT = re.compile(r"(windows|system32|syswow64)", re.I)

def dll_deps(path):
    try:
        out = subprocess.check_output(["objdump", "-p", path], text=True, stderr=subprocess.DEVNULL, errors="replace")
    except Exception:
        return []
    deps = []
    for line in out.splitlines():
        m = re.search(r"DLL Name:\s*(\S+)", line, re.I)
        if m:
            deps.append(m.group(1))
    return deps

def find_dll(name, scrcpy_dir):
    local = os.path.join(tools, name)
    if os.path.isfile(local):
        return local
    dirs = [scrcpy_dir, os.path.dirname(scrcpy)]
    dirs += os.environ.get("PATH", "").split(os.pathsep)
    dirs += [r"C:\Program Files\scrcpy", r"C:\scrcpy"]
    for d in dirs:
        if not d: continue
        cand = os.path.join(d, name)
        if os.path.isfile(cand):
            return cand
        try:
            for f in os.listdir(d):
                if f.lower() == name.lower():
                    return os.path.join(d, f)
        except Exception:
            pass
    return None

exe_dir = os.path.dirname(os.path.realpath(scrcpy))
q = deque([os.path.realpath(scrcpy)])
seen = set()
copied = 0
while q:
    p = q.popleft()
    if p in seen or not os.path.isfile(p):
        continue
    seen.add(p)
    for dep in dll_deps(p):
        if SYSTEM_HINT.search(dep):
            continue
        dest = os.path.join(tools, dep)
        if not os.path.isfile(dest):
            src = find_dll(dep, exe_dir)
            if src and os.path.isfile(src) and os.path.realpath(src) != p:
                shutil.copy2(src, dest)
                copied += 1
                q.append(dest)
print(f"copied {copied} dlls")
PY

Write-Host "== Rename product to SideLoador-Android-bundled =="
$BundledOut = Join-Path (Split-Path -Parent $Out) "SideLoador-Android-bundled"
if (Test-Path $BundledOut) { Remove-Item -Recurse -Force $BundledOut }
New-Item -ItemType Directory -Path $BundledOut -Force | Out-Null
# Copy everything from Release (including tools) into -bundled folder
Get-ChildItem -Path $Out -Force | ForEach-Object {
  Copy-Item $_.FullName -Destination $BundledOut -Recurse -Force
}
$Tools = Join-Path $BundledOut "tools"

Write-Host "== Verify =="
& (Join-Path $Tools "adb.exe") version | Select-Object -First 1
& (Join-Path $Tools "scrcpy.exe") --version | Select-Object -First 1

Write-Host "Output: $BundledOut"
Write-Host "Mode: BUNDLED tools ($Tools)"
Write-Host "Product name: SideLoador-Android-bundled"
Write-Host "Done."
