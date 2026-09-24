#!/usr/bin/env bash
# Build mobile-app APK and copy into desktop assets/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/mobile_app"

if [[ -z "${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-}" ]]; then
  if [[ -d "$HOME/Library/Android/sdk" ]]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
  fi
fi

echo "==> ANDROID_HOME=${ANDROID_HOME:-unset}"

if [[ ! -f gradlew ]]; then
  echo "==> Generating gradle wrapper"
  if command -v gradle >/dev/null 2>&1; then
    gradle wrapper --gradle-version 8.7
  else
    echo "gradle not found — install: brew install gradle"
    exit 1
  fi
fi

./gradlew :app:assembleDebug

APK="$ROOT/mobile_app/app/build/outputs/apk/debug/app-debug.apk"
mkdir -p "$ROOT/assets"
cp -f "$APK" "$ROOT/assets/scrcpy_bridge_mobile.apk"
echo "==> Copied to assets/scrcpy_bridge_mobile.apk"
