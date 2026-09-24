#!/usr/bin/env bash
# Bootstrap Scrcpy Bridge desktop app on macOS (priority).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "==> Checking tools"
command -v adb >/dev/null || { echo "missing adb"; exit 1; }
command -v scrcpy >/dev/null || echo "warn: scrcpy not on PATH"
command -v xcodebuild >/dev/null || echo "warn: Xcode CLT missing"

# Locate flutter
FLUTTER=""
if command -v flutter >/dev/null 2>&1; then
  FLUTTER=flutter
elif [[ -x "$HOME/flutter-sdk/bin/flutter" ]]; then
  FLUTTER="$HOME/flutter-sdk/bin/flutter"
elif [[ -x /opt/homebrew/share/flutter/bin/flutter ]]; then
  FLUTTER=/opt/homebrew/share/flutter/bin/flutter
fi

if [[ -z "$FLUTTER" ]]; then
  echo "Flutter SDK not found."
  echo "Install options:"
  echo "  brew install --cask flutter"
  echo "  git clone --depth 1 -b stable https://github.com/flutter/flutter.git \"\$HOME/flutter-sdk\""
  exit 1
fi

echo "==> Using Flutter: $FLUTTER"
"$FLUTTER" --version

echo "==> Enable desktop targets"
"$FLUTTER" config --enable-macos-desktop >/dev/null
"$FLUTTER" config --enable-windows-desktop >/dev/null
"$FLUTTER" config --enable-linux-desktop >/dev/null

echo "==> Ensure platform shells (keeps existing lib/)"
"$FLUTTER" create --platforms=macos,windows,linux --project-name scrcpy_bridge .

echo "==> flutter pub get"
"$FLUTTER" pub get

echo "==> Done. Run with:"
echo "    $FLUTTER run -d macos"
