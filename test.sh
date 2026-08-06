#!/usr/bin/env bash
# Run before every push to v1. A syntax error or a broken helper in lib.sh
# breaks every installer that fetches it, on every machine, at once.
#
#   bash test.sh
#
# These tests never touch apt, never install anything, and never reach the
# network. They check the parts that are the same on every machine.

cd "$(dirname "$0")" || exit 1

echo "== bash -n"
bash -n lib.sh || { echo "  SYNTAX ERROR in lib.sh"; exit 1; }
echo "  ok"

echo "== loads cleanly under set -euo pipefail, silently, without exiting"
out="$(bash -c 'set -euo pipefail; eval "$(cat lib.sh)"; printf "%s" "$KB_LIB_VERSION"' 2>&1)" || {
  echo "  FAILED to load: $out"; exit 1; }
case "$out" in
  [0-9]*) echo "  ok (version $out)" ;;
  *) echo "  FAILED: loading printed something or lost the version: [$out]"; exit 1 ;;
esac

echo "== every documented function is defined"
missing="$(bash -c 'eval "$(cat lib.sh)"
for f in log warn die ok say sudo_cmd kb_is_root kb_apt_package_for need_tools \
         ensure_claude_code kb_persist_path ensure_gh have_tty ask ask_yes \
         ensure_claude_signin ensure_gh_auth reexec_as_user handoff; do
  declare -F "$f" >/dev/null || printf "%s " "$f"
done')"
[ -z "$missing" ] || { echo "  MISSING: $missing"; exit 1; }
echo "  ok"

echo "== behaviour"
bash <<'TEST'
eval "$(cat lib.sh)"
pass=0; fail=0
t(){ if [ "$2" = "$3" ]; then printf "  ok    %s\n" "$1"; pass=$((pass+1));
     else printf "  FAIL  %s\n        want=[%s]\n        got =[%s]\n" "$1" "$3" "$2"; fail=$((fail+1)); fi; }

t "xz maps to the xz-utils package"    "$(kb_apt_package_for xz)"        "xz-utils"
t "sha256sum maps to coreutils"        "$(kb_apt_package_for sha256sum)" "coreutils"
t "an ordinary name maps to itself"    "$(kb_apt_package_for git)"       "git"

out="$(need_tools bash 2>&1)"; rc=$?
t "need_tools says nothing when all present" "$out" ""
t "need_tools exits 0 when all present"      "$rc"  "0"

# No terminal in a heredoc, so every ask must fall back instead of hanging.
t "ask falls back to its default"      "$(ask 'Repo name' 'my-hub')" "my-hub"
t "ask with no default returns empty"  "$(ask 'Anything')"           ""
if ask_yes "Proceed" "y"; then t "ask_yes honours a y default" yes yes; else t "ask_yes honours a y default" no yes; fi
if ask_yes "Proceed" "n"; then t "ask_yes honours an n default" yes no; else t "ask_yes honours an n default" no no; fi
if have_tty; then t "have_tty is false when piped" true false; else t "have_tty is false when piped" false false; fi

# THE su REGRESSION, all four cases.
#
# On a real box the installer switches to the assistant's account, and from there
# /dev/tty cannot be OPENED (it belongs to the login that opened it) while the
# inherited descriptors still work. The old check only tried to open, so every
# real run reported "no terminal" and stopped at the sign-in with a terminal
# sitting right there. Found on Ubuntu 24.04, 2026-08-06.
#
# The two conditions are their own functions precisely so this can be tested
# without a real terminal - which is the only reason the bug reached a live box.
resolve_with() {   # resolve_with <stdin-is-tty> <can-open-tty>
  ( _in="$1"; _open="$2"
    kb_stdin_is_tty() { [ "$_in"   = yes ]; }
    kb_can_open_tty() { [ "$_open" = yes ]; }
    KB_TTY=""; kb_resolve_tty; printf '%s' "$KB_TTY" )
}
t "after su: stdin is the tty, /dev/tty refuses to open" "$(resolve_with yes no )" "inherited"
t "curl | bash as root: stdin is the pipe, /dev/tty opens" "$(resolve_with no  yes)" "device"
t "plain interactive shell: both are true, prefer inherited" "$(resolve_with yes yes)" "inherited"
t "genuinely headless: neither" "$(resolve_with no  no )" "none"

# Called out of order, the message must name the cause rather than crash.
out="$( (handoff "x") 2>&1 )"; rc=$?
t "handoff before ensure_claude_code exits 1" "$rc" "1"
case "$out" in *"before ensure_claude_code"*) t "that error names the cause" yes yes ;;
               *) t "that error names the cause" "$out" yes ;; esac
out="$( (KB_CLAUDE_BIN=/bin/true; ensure_claude_signin) 2>&1 )"
case "$out" in *"no terminal"*) t "headless sign-in fails honestly" yes yes ;;
               *) t "headless sign-in fails honestly" "$out" yes ;; esac

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
TEST
rc=$?

echo
[ "$rc" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$rc"
