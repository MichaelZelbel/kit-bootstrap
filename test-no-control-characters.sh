#!/usr/bin/env bash
# test-no-control-characters.sh — refuse a source file whose bytes do not spell what the
# screen shows.
#
# WHY THIS EXISTS (2026-08-16). join.ps1 built the path to the prompt harvester like this:
#
#     $installed = Join-Path $HOME '.local<0x08>in\prompt-harvest.js'
#
# A literal BACKSPACE byte sat where the backslash-b of '.local\bin' was meant. The path could
# never exist. The fallback beside it does not exist for a reader's hub either, so the function
# returned before scheduling anything, and EVERY Windows reader got no prompt archive at all,
# silently, while the installer reported success.
#
# It survived because it is invisible three times over: the screen renders it as ".localin",
# grep for "local.bin" does not match it, and grep for "localin" does not match it either. Only
# the bytes tell the truth. This is the second time a control character has switched something
# off in this codebase, which is once more than a thing should be allowed to happen by accident.
#
# Tabs, newlines and carriage returns are fine. Everything else in C0, and DEL, is not.
#
# Usage: bash test-no-control-characters.sh [dir]
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")" && pwd)}"
PY=""
for c in python3 python; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
[ -n "$PY" ] || { echo "no python, cannot check bytes"; exit 0; }

"$PY" - "$ROOT" <<'PYEOF'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
# Everything in C0 except tab (09), newline (0a) and carriage return (0d), plus DEL (7f).
CTRL = re.compile(rb'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]')
SUFFIXES = {".ps1", ".sh", ".py", ".js", ".json", ".iss", ".cmd", ".bat", ".md", ".txt", ".yml", ".yaml"}

bad = []
checked = 0
for p in sorted(root.rglob("*")):
    if not p.is_file() or ".git" in p.parts:
        continue
    if p.suffix.lower() not in SUFFIXES:
        continue
    try:
        b = p.read_bytes()
    except Exception:
        continue
    checked += 1
    for m in CTRL.finditer(b):
        line = b[:m.start()].count(b"\n") + 1
        shown = b[max(0, m.start() - 30):m.start() + 20].replace(b"\n", b" ")
        bad.append((p.relative_to(root), line, m.group()[0], shown.decode("utf-8", "replace")))

print("  checked %d source files" % checked)
for rel, line, byte, shown in bad:
    print("  FAIL %s:%d holds byte 0x%02x, which is invisible on screen: ...%s..."
          % (rel, line, byte, shown))
if bad:
    print("\n  %d control character(s). The bytes do not spell what the screen shows, which is"
          % len(bad))
    print("  how a path that can never exist looked correct for weeks.")
    sys.exit(1)
print("  ok - no file hides a control character")
PYEOF
