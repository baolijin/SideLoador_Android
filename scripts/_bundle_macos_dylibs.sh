#!/usr/bin/env bash
# macOS-only: copy scrcpy dylib deps and rewrite install names into $1 (tools dir).
set -euo pipefail
TOOLS="$1"
LIBDIR="$TOOLS/lib"
SCRCPY="$TOOLS/scrcpy"
mkdir -p "$LIBDIR"

python3 - <<'PY' "$SCRCPY" "$LIBDIR"
import os, sys, subprocess, shutil
from collections import deque

scrcpy_bin, libdir = sys.argv[1], sys.argv[2]
SYSTEM = ("/usr/lib", "/System/", "/usr/lib/system")

def otool_deps(path):
    try:
        out = subprocess.check_output(["otool", "-L", path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return []
    deps = []
    for line in out.splitlines()[1:]:
        p = line.strip().split("(")[0].strip()
        if p and not p.startswith(SYSTEM):
            deps.append(p)
    return deps

def find_by_basename(name, start_dirs):
    for base in start_dirs:
        if not base or not os.path.isdir(base):
            continue
        direct = os.path.join(base, name)
        if os.path.isfile(direct) or os.path.islink(direct):
            return os.path.realpath(direct)
    for base in start_dirs:
        if not base or not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            if name in files:
                return os.path.realpath(os.path.join(root, name))
            if root.count(os.sep) - base.count(os.sep) > 6:
                dirs.clear()
    return None

def resolve(dep, binary_dir):
    if dep.startswith(("@rpath/", "@loader_path/", "@executable_path/")):
        name = os.path.basename(dep)
        return find_by_basename(name, [binary_dir, "/opt/homebrew/lib", "/opt/homebrew/opt"])
    if os.path.isfile(dep) or os.path.islink(dep):
        return os.path.realpath(dep)
    name = os.path.basename(dep)
    for base in ("/opt/homebrew/lib", "/opt/homebrew/opt", "/opt/homebrew/Cellar"):
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            if name in files:
                return os.path.realpath(os.path.join(root, name))
            stem = name[:-6] if name.endswith(".dylib") else name
            for f in files:
                if f.endswith(".dylib") and f.startswith(stem + "."):
                    return os.path.realpath(os.path.join(root, f))
            if root.count(os.sep) - base.count(os.sep) > 6:
                dirs.clear()
    return None

short_to_real = {}
seen = set()
q = deque([os.path.realpath(scrcpy_bin)])
collected = []
while q:
    p = q.popleft()
    if p in seen or not os.path.isfile(p):
        continue
    seen.add(p)
    if p != os.path.realpath(scrcpy_bin):
        collected.append(p)
    for d in otool_deps(p):
        real = resolve(d, os.path.dirname(p))
        if real and os.path.isfile(real):
            short_to_real[os.path.basename(d)] = real
            q.append(real)

for real in collected:
    dest = os.path.join(libdir, os.path.basename(real))
    if not os.path.exists(dest):
        shutil.copy2(real, dest)

for short, real in short_to_real.items():
    short_path = os.path.join(libdir, short)
    real_name = os.path.basename(real)
    if not os.path.exists(os.path.join(libdir, real_name)) and os.path.isfile(real):
        shutil.copy2(real, os.path.join(libdir, real_name))
    if short != real_name and not os.path.lexists(short_path):
        try:
            os.symlink(real_name, short_path)
        except FileExistsError:
            pass

for f in list(os.listdir(libdir)):
    fp = os.path.join(libdir, f)
    if os.path.islink(fp) or not os.path.isfile(fp):
        continue
    for d in otool_deps(fp):
        short = os.path.basename(d)
        if short == f:
            continue
        short_path = os.path.join(libdir, short)
        if not os.path.lexists(short_path):
            stem = short[:-6] if short.endswith(".dylib") else short
            candidates = [x for x in os.listdir(libdir) if x.endswith(".dylib") and x.startswith(stem)]
            if candidates:
                try:
                    os.symlink(candidates[0], short_path)
                except FileExistsError:
                    pass
print("lib files:", sorted(os.listdir(libdir)))
PY

python3 - <<'PY' "$TOOLS"
import os, sys, subprocess, glob
tools = sys.argv[1]
libdir = os.path.join(tools, "lib")

def deps(path):
    try:
        out = subprocess.check_output(["otool", "-L", path], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return []
    res = []
    for line in out.splitlines()[1:]:
        p = line.strip().split("(")[0].strip()
        if p:
            res.append(p)
    return res

def target_name(dep, available):
    base = os.path.basename(dep)
    if base in available:
        return base
    if base.endswith(".dylib"):
        stem = base[:-6]
        for a in available:
            if a.startswith(stem + ".") and a.endswith(".dylib"):
                return a
            if a.startswith(stem) and a.endswith(".dylib"):
                return a
    return None

def rewrite(path, is_exe):
    available = set(os.listdir(libdir))
    for dep in deps(path):
        if dep.startswith("/usr/lib") or dep.startswith("/System/"):
            continue
        name = target_name(dep, available)
        if not name:
            if dep.startswith("/") and not dep.startswith("@"):
                print(f"WARN unresolved {os.path.basename(path)}: {dep}")
            continue
        new = f"@executable_path/lib/{name}" if is_exe else f"@loader_path/{name}"
        if dep == new or dep.startswith("@executable_path/lib/") or dep.startswith("@loader_path/"):
            continue
        try:
            subprocess.check_call(["install_name_tool", "-change", dep, new, path])
        except subprocess.CalledProcessError as e:
            print(f"FAIL {os.path.basename(path)}: {dep}: {e}")
    if is_exe:
        try:
            subprocess.check_call(["install_name_tool", "-add_rpath", "@executable_path/lib", path], stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            pass
        try:
            subprocess.check_call(["install_name_tool", "-delete_rpath", "/opt/homebrew/lib", path], stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            pass

for p in sorted(glob.glob(os.path.join(libdir, "*"))):
    if os.path.islink(p) or not os.path.isfile(p):
        continue
    rewrite(p, is_exe=False)
rewrite(os.path.join(tools, "scrcpy"), is_exe=True)

for p in [os.path.join(tools, "scrcpy")] + [
    os.path.join(libdir, f) for f in os.listdir(libdir)
    if os.path.isfile(os.path.join(libdir, f)) and not os.path.islink(os.path.join(libdir, f))
]:
    subprocess.call(["codesign", "-f", "-s", "-", p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print("rewrite done")
PY
