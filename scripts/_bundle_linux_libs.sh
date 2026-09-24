#!/usr/bin/env bash
# Linux: copy adb/scrcpy shared library deps into tools/lib and fix RPATH.
# Run on a Linux machine that has scrcpy + adb installed.
set -euo pipefail
TOOLS="$1"
LIBDIR="$2"
SCRCPY="$TOOLS/scrcpy"
ADB="$TOOLS/adb"
mkdir -p "$LIBDIR"

python3 - <<'PY' "$SCRCPY" "$ADB" "$LIBDIR"
import os, sys, subprocess, shutil, re
from collections import deque

scrcpy_bin, adb_bin, libdir = sys.argv[1], sys.argv[2], sys.argv[3]
SYSTEM_PREFIX = re.compile(r"^(/lib|/usr/lib|/lib64|/usr/lib64)/(?!x86_64-linux-gnu/(lib(av|SDL|usb)|libssl|libcrypto))")

def ldd_deps(path):
    try:
        out = subprocess.check_output(["ldd", path], text=True, stderr=subprocess.DEVNULL, errors="replace")
    except Exception:
        return []
    deps = []
    for line in out.splitlines():
        line = line.strip()
        if "=>" in line:
            rhs = line.split("=>", 1)[1].strip().split()[0]
            if rhs.startswith("/") and os.path.isfile(rhs):
                deps.append(rhs)
        elif line.startswith("/") and "ld-linux" not in line:
            if os.path.isfile(line):
                deps.append(line)
    return deps

def is_system(path):
    # Keep only non-core libs that scrcpy typically needs from /usr/lib
    # Copy anything not matching strict system loaders
    if "ld-linux" in path or path.endswith("libc.so.6") or path.endswith("libm.so.6"):
        return True
    # copy homebrew-like / non-standard locations always
    if path.startswith("/usr/lib/x86_64-linux-gnu/") or path.startswith("/lib/x86_64-linux-gnu/"):
        # still bundle if it's av/sdl/usb/ssl family used by scrcpy
        base = os.path.basename(path)
        keywords = ("avcodec", "avformat", "avutil", "swresample", "SDL", "usb-1.0", "ssl.so", "crypto.so", "x264", "x265", "vpx", "opus", "dav1d")
        if any(k in base for k in keywords):
            return False
        return True
    if path.startswith("/usr/lib/") or path.startswith("/lib/"):
        return True
    return False

seen = set()
q = deque([os.path.realpath(scrcpy_bin), os.path.realpath(adb_bin)])
while q:
    p = q.popleft()
    if p in seen or not os.path.isfile(p):
        continue
    seen.add(p)
    for d in ldd_deps(p):
        if is_system(d):
            continue
        dest = os.path.join(libdir, os.path.basename(d))
        if not os.path.isfile(dest):
            shutil.copy2(d, dest)
        q.append(d)

# Also copy SONAME aliases
for f in os.listdir(libdir):
    fp = os.path.join(libdir, f)
    # ensure linker can find via rpath on scrcpy
print("lib files:", sorted(os.listdir(libdir)))
PY

# Fix rpath so scrcpy finds tools/lib next to itself
if command -v patchelf >/dev/null; then
  # binary lives in tools/, libs in tools/lib
  patchelf --set-rpath '$ORIGIN/lib' "$SCRCPY" || true
  # also absolute fallback for verify
  patchelf --add-rpath "$(realpath "$LIBDIR")" "$SCRCPY" 2>/dev/null || true
  # re-wrap: prefer only $ORIGIN/lib
  ORIGIN_RPATH='$ORIGIN/../lib'
  # tools/scrcpy -> tools/lib is $ORIGIN/lib
  patchelf --set-rpath '$ORIGIN/lib' "$SCRCPY" || true
  # Set rpath on each copied .so to $ORIGIN
  for so in "$LIBDIR"/*.so*; do
    [[ -f "$so" ]] || continue
    patchelf --set-rpath '$ORIGIN' "$so" 2>/dev/null || true
  done
  echo "patchelf rpath set"
else
  echo "WARN: patchelf not found — install it for reliable RPATH fix (apt install patchelf)"
fi

echo -n "ldd scrcpy: "
if ldd "$SCRCPY" 2>/dev/null | grep -q "not found"; then
  ldd "$SCRCPY" | grep "not found" || true
  echo "HAS MISSING"
else
  echo "OK"
fi
