#!/usr/bin/env bash
# Package SideLoador-Android using the HOST's existing adb / scrcpy.
# Works for macos | windows | linux (pass --platform or PLATFORM env).
# Target machine must already have adb + scrcpy (or set ADB_PATH / SCRCPY_PATH).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PATH="${HOME}/flutter-sdk/bin:${PATH}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

PLATFORM="${PLATFORM:-}"
if [[ -z "$PLATFORM" ]]; then
  case "$(uname -s)" in
    Darwin) PLATFORM=macos ;;
    Linux)  PLATFORM=linux ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
    *) PLATFORM=macos ;;
  esac
fi
# allow --platform foo
if [[ "${1:-}" == "--platform" && -n "${2:-}" ]]; then
  PLATFORM="$2"
fi

case "$PLATFORM" in
  macos)   flutter build macos --release ;;
  windows) flutter build windows --release ;;
  linux)   flutter build linux --release ;;
  *) echo "unknown platform: $PLATFORM (use macos|windows|linux)" >&2; exit 1 ;;
esac

echo "== Host tools check =="
command -v adb >/dev/null || echo "warn: adb not on PATH (runtime will search known paths)"
command -v scrcpy >/dev/null || echo "warn: scrcpy not on PATH (runtime will search known paths)"
echo "adb   = $(command -v adb 2>/dev/null || echo 'not found')"
echo "scrcpy= $(command -v scrcpy 2>/dev/null || echo 'not found')"

echo "== Mode: HOST (uses adb/scrcpy installed on target) platform=$PLATFORM =="

# Remove leftover bundled tools from a previous bundled build
case "$PLATFORM" in
  macos)
    APP="$ROOT/build/macos/Build/Products/Release/SideLoador-Android.app"
    OUT="$APP"
    rm -rf "$APP/Contents/MacOS/tools" 2>/dev/null || true
    rm -rf "/Applications/SideLoador-Android.app" 2>/dev/null || true
    cp -R "$APP" /Applications/SideLoador-Android.app
    echo "Installed to /Applications/SideLoador-Android.app"
    ;;
  windows)
    OUT="$ROOT/build/windows/x64/runner/Release"
    # Flutter windows output dir
    if [[ ! -d "$OUT" ]]; then
      OUT="$(find "$ROOT/build/windows" -type d -name Release 2>/dev/null | head -1 || true)"
    fi
    rm -rf "$OUT/tools" 2>/dev/null || true
    echo "Output: $OUT"
    ;;
  linux)
    OUT="$ROOT/build/linux/x64/release/bundle"
    if [[ ! -d "$OUT" ]]; then
      OUT="$(find "$ROOT/build/linux" -path '*/bundle' -type d 2>/dev/null | head -1 || true)"
    fi
    rm -rf "$OUT/tools" 2>/dev/null || true
    echo "Output: $OUT"
    ;;
esac

echo "Done. platform=$PLATFORM mode=HOST"
