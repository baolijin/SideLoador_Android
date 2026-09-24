#!/usr/bin/env bash
# Package SideLoador-Android with adb + scrcpy BUNDLED into the app.
# Output product name gets a "-bundled" suffix (e.g. SideLoador-Android-bundled.app).
# - macOS:  dylibs + install_name_tool (run on a Mac with Homebrew scrcpy)
# - Linux:  .so + patchelf/RPATH (run on Linux with scrcpy installed)
# - Windows: adb.exe/scrcpy.exe + DLLs (run on Windows; see also .ps1)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/flutter-sdk/bin:${PATH}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

APP_BASE_NAME="SideLoador-Android"
APP_BUNDLED_NAME="SideLoador-Android-bundled"

PLATFORM="${PLATFORM:-}"
if [[ -z "$PLATFORM" ]]; then
  case "$(uname -s)" in
    Darwin) PLATFORM=macos ;;
    Linux)  PLATFORM=linux ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
    *) PLATFORM=macos ;;
  esac
fi
if [[ "${1:-}" == "--platform" && -n "${2:-}" ]]; then
  PLATFORM="$2"
fi

case "$PLATFORM" in
  macos)   BUILD_TARGET=macos ;;
  windows) BUILD_TARGET=windows ;;
  linux)   BUILD_TARGET=linux ;;
  *) echo "unknown platform: $PLATFORM" >&2; exit 1 ;;
esac

# Locate host tools
if [[ "$PLATFORM" == "windows" ]]; then
  ADB_BIN="${ADB_PATH:-}"
  if [[ -z "$ADB_BIN" ]]; then
    for c in adb.exe "$(command -v adb.exe 2>/dev/null || true)" \
             "C:/Android/platform-tools/adb.exe" \
             "C:/Program Files/platform-tools/adb.exe"; do
      [[ -n "$c" && -f "$c" ]] && ADB_BIN="$c" && break
    done
  fi
  SCRCPY_BIN="${SCRCPY_PATH:-scrcpy.exe}"
else
  ADB_BIN="${ADB_PATH:-$HOME/Library/Android/sdk/platform-tools/adb}"
  [[ -f "$ADB_BIN" ]] || ADB_BIN="$(command -v adb 2>/dev/null || true)"
  [[ -f "$ADB_BIN" ]] || ADB_BIN="/usr/lib/android-sdk/platform-tools/adb"
  SCRCPY_BIN="${SCRCPY_PATH:-$(command -v scrcpy 2>/dev/null || true)}"
  [[ -n "$SCRCPY_BIN" && -x "$SCRCPY_BIN" ]] || SCRCPY_BIN="/opt/homebrew/bin/scrcpy"
  [[ -x "$SCRCPY_BIN" ]] || SCRCPY_BIN="/usr/bin/scrcpy"
fi

if [[ ! -f "$ADB_BIN" && ! -x "$ADB_BIN" ]]; then
  echo "error: adb not found (set ADB_PATH)" >&2
  exit 1
fi
if [[ ! -f "$SCRCPY_BIN" && ! -x "$SCRCPY_BIN" ]]; then
  echo "error: scrcpy not found (set SCRCPY_PATH)" >&2
  exit 1
fi
# resolve symlink
SCRCPY_BIN="$(python3 -c "import os;print(os.path.realpath('$SCRCPY_BIN'))")"
ADB_BIN="$(python3 -c "import os;print(os.path.realpath('$ADB_BIN'))")"

echo "== [1/5] flutter build $BUILD_TARGET --release =="
flutter build "$BUILD_TARGET" --release

# Resolve Flutter build output (base name, before -bundled rename)
case "$PLATFORM" in
  macos)
    FLUTTER_OUT="$ROOT/build/macos/Build/Products/Release/${APP_BASE_NAME}.app"
    ;;
  windows)
    FLUTTER_OUT="$ROOT/build/windows/x64/runner/Release"
    if [[ ! -d "$FLUTTER_OUT" ]]; then
      FLUTTER_OUT="$(find "$ROOT/build/windows" -type d -name Release 2>/dev/null | head -1 || true)"
    fi
    ;;
  linux)
    FLUTTER_OUT="$ROOT/build/linux/x64/release/bundle"
    if [[ ! -d "$FLUTTER_OUT" ]]; then
      FLUTTER_OUT="$(find "$ROOT/build/linux" -path '*/bundle' -type d 2>/dev/null | head -1 || true)"
    fi
    ;;
esac

if [[ -z "${FLUTTER_OUT:-}" || ! -d "$FLUTTER_OUT" ]]; then
  echo "error: build output not found for $PLATFORM" >&2
  exit 1
fi

# Bundle tools into the Flutter output first (same layout ToolPaths expects)
case "$PLATFORM" in
  macos)   TOOLS="$FLUTTER_OUT/Contents/MacOS/tools" ;;
  windows) TOOLS="$FLUTTER_OUT/tools" ;;
  linux)   TOOLS="$FLUTTER_OUT/tools" ;;
esac
LIBDIR="$TOOLS"
[[ "$PLATFORM" != "windows" ]] && LIBDIR="$TOOLS/lib"

echo "== [2/5] Copy tools into $TOOLS =="
rm -rf "$TOOLS"
mkdir -p "$LIBDIR"

# Copy binaries with platform-correct names
if [[ "$PLATFORM" == "windows" ]]; then
  cp -f "$ADB_BIN" "$TOOLS/adb.exe"
  cp -f "$SCRCPY_BIN" "$TOOLS/scrcpy.exe"
else
  cp -f "$ADB_BIN" "$TOOLS/adb"
  chmod +x "$TOOLS/adb"
  cp -f "$SCRCPY_BIN" "$TOOLS/scrcpy"
  chmod +x "$TOOLS/scrcpy"
fi

echo "== [3/5] Bundle native deps ($PLATFORM) =="
case "$PLATFORM" in
  macos)
    # Reuse the mac-specific dylib collector/rewriter
    bash "$ROOT/scripts/_bundle_macos_dylibs.sh" "$TOOLS"
    ;;
  linux)
    bash "$ROOT/scripts/_bundle_linux_libs.sh" "$TOOLS" "$LIBDIR"
    ;;
  windows)
    # Copy non-system DLLs next to the exes (Windows loads from exe dir)
    python3 - <<'PY' "$TOOLS"
import os, sys, subprocess, shutil, re
from collections import deque

tools = sys.argv[1]
SYSTEM_HINT = re.compile(r"(windows|system32|syswow64)", re.I)

def dll_deps(path):
    try:
        out = subprocess.check_output(["objdump", "-p", path], text=True, stderr=subprocess.DEVNULL, errors="replace")
    except Exception:
        try:
            out = subprocess.check_output(["ntldd", "-R", path], text=True, stderr=subprocess.DEVNULL, errors="replace")
        except Exception:
            return []
    deps = []
    for line in out.splitlines():
        # objdump: "DLL Name: avcodec-61.dll"
        m = re.search(r"DLL Name:\s*(\S+)", line, re.I)
        if m:
            deps.append(m.group(1))
        elif "=>" in line:
            left = line.split("=>")[0].strip().split()[-1]
            if left.lower().endswith(".dll"):
                deps.append(left)
    return deps

def find_dll(name, exe_dir):
    # next to scrcpy / in tools already
    local = os.path.join(tools, name)
    if os.path.isfile(local):
        return local
    # search common Windows scrcpy / PATH locations
    search_dirs = [
        exe_dir,
        os.path.dirname(os.path.realpath(os.path.join(tools, "scrcpy.exe"))),
        r"C:\Program Files\scrcpy",
        r"C:\scrcpy",
    ]
    path_dirs = os.environ.get("PATH", "").split(os.pathsep)
    search_dirs.extend(path_dirs)
    for d in search_dirs:
        if not d:
            continue
        cand = os.path.join(d, name)
        if os.path.isfile(cand):
            return cand
        # case-insensitive scan of dir
        try:
            for f in os.listdir(d):
                if f.lower() == name.lower():
                    return os.path.join(d, f)
        except Exception:
            pass
    return None

exe = os.path.join(tools, "scrcpy.exe")
exe_dir = os.path.dirname(os.path.realpath(exe))
q = deque([exe])
seen = set()
copied = 0
while q:
    p = q.popleft()
    rp = os.path.realpath(p)
    if rp in seen or not os.path.isfile(rp):
        continue
    seen.add(rp)
    for dep in dll_deps(rp):
        if SYSTEM_HINT.search(dep):
            continue
        dest = os.path.join(tools, dep)
        if not os.path.isfile(dest):
            src = find_dll(dep, exe_dir)
            if src and os.path.isfile(src) and os.path.realpath(src) != rp:
                shutil.copy2(src, dest)
                copied += 1
                q.append(dest)
print(f"copied {copied} dlls into {tools}")
PY
    ;;
esac

echo "== [4/5] Rename product to ${APP_BUNDLED_NAME} =="
FINAL_OUT=""
case "$PLATFORM" in
  macos)
    DEST="$ROOT/build/macos/Build/Products/Release/${APP_BUNDLED_NAME}.app"
    rm -rf "$DEST"
    mv "$FLUTTER_OUT" "$DEST"
    FINAL_OUT="$DEST"
    ;;
  linux)
    DEST="$ROOT/build/linux/x64/release/${APP_BUNDLED_NAME}"
    rm -rf "$DEST"
    mv "$FLUTTER_OUT" "$DEST"
    FINAL_OUT="$DEST"
    ;;
  windows)
    # Keep Flutter Release tree; also publish a clearly named folder
    DEST="$ROOT/build/windows/x64/runner/${APP_BUNDLED_NAME}"
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -R "$FLUTTER_OUT/." "$DEST/"
    FINAL_OUT="$DEST"
    ;;
esac
echo "Renamed to: $FINAL_OUT"

echo "== [5/5] Verify =="
TOOLS_FINAL=""
case "$PLATFORM" in
  macos)
    TOOLS_FINAL="$FINAL_OUT/Contents/MacOS/tools"
    echo -n "adb:    "; "$TOOLS_FINAL/adb" version 2>&1 | head -1 || true
    echo -n "scrcpy: "; "$TOOLS_FINAL/scrcpy" --version 2>&1 | head -1 || true
    if otool -L "$TOOLS_FINAL/scrcpy" 2>/dev/null | grep -q '/opt/homebrew/'; then
      echo "WARN: scrcpy still references /opt/homebrew"
    else
      echo "OK: scrcpy has no /opt/homebrew absolute paths"
    fi
    rm -rf "/Applications/${APP_BUNDLED_NAME}.app" 2>/dev/null || true
    cp -R "$FINAL_OUT" "/Applications/${APP_BUNDLED_NAME}.app"
    echo "Installed to /Applications/${APP_BUNDLED_NAME}.app"
    ;;
  linux)
    TOOLS_FINAL="$FINAL_OUT/tools"
    echo -n "adb:    "; "$TOOLS_FINAL/adb" version 2>&1 | head -1 || true
    echo -n "scrcpy: "; "$TOOLS_FINAL/scrcpy" --version 2>&1 | head -1 || true
    if command -v ldd >/dev/null; then
      if ldd "$TOOLS_FINAL/scrcpy" 2>/dev/null | grep -q "not found"; then
        echo "WARN: scrcpy has missing shared libs:"
        ldd "$TOOLS_FINAL/scrcpy" | grep "not found" || true
      else
        echo "OK: scrcpy shared libs resolved"
      fi
    fi
    ;;
  windows)
    TOOLS_FINAL="$FINAL_OUT/tools"
    echo -n "adb:    "; "$TOOLS_FINAL/adb.exe" version 2>&1 | head -1 || true
    echo -n "scrcpy: "; "$TOOLS_FINAL/scrcpy.exe" --version 2>&1 | head -1 || true
    ;;
esac

echo "Output: $FINAL_OUT"
echo "Mode: BUNDLED tools ($TOOLS_FINAL)"
echo "Product name: ${APP_BUNDLED_NAME}"
echo "Done. platform=$PLATFORM"
