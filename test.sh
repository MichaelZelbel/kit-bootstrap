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
         kb_stdin_is_tty kb_can_open_tty kb_resolve_tty kb_tell kb_read \
         kb_run_interactive kb_skip_claude_first_run kb_grant_working_permissions \
         ensure_claude_signin ensure_gh_auth reexec_as_user handoff \
         kb_ai_memory_path kb_seed_memory_index kb_link_ai_memory; do
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

# EXTRA DIRECTORIES. The step sheets the installer must follow live outside the
# folder Claude is started in, and Read(**) only covers that folder. They go into
# the settings file, NOT onto the command line: --add-dir takes a variable number
# of values, so a trailing prompt argument is swallowed as one more directory. On
# a live box that left Claude Code sitting at an empty prompt, doing nothing.
if command -v jq >/dev/null 2>&1; then
  _e=$(mktemp -d); mkdir -p "$_e/.claude" "$_e/kb_a" "$_e/kb_b"
  ( HOME="$_e"; KB_EXTRA_DIRS="$_e/kb_a $_e/kb_b $_e/kb_missing"
    kb_grant_working_permissions "settings/server-profile.json" ) >/dev/null 2>&1
  t "existing extra folders are recorded"     "$(jq -r '.permissions.additionalDirectories | length' "$_e/.claude/settings.json")" "2"
  t "a missing folder is dropped"     "$(jq -r '.permissions.additionalDirectories | map(select(endswith("kb_missing"))) | length' "$_e/.claude/settings.json")" "0"
  # Claude Code ignores Write() and Glob() rules entirely and says so on startup;
  # only Edit() and Read() are matched. A deny rule that never fires is worse
  # than no deny rule, because it reads like protection.
  t "no rule type that Claude Code ignores"     "$(jq -r '[.permissions.allow[], .permissions.deny[]] | map(select(startswith("Write(") or startswith("Glob("))) | length' "$_e/.claude/settings.json")" "0"
  rm -rf "$_e"
fi

# THE FIRST-RUN GATES. A fresh Claude Code asks three questions before it will
# read a prompt, and one of them starts a SECOND sign-in seconds after the first
# finished. Answering them must not clobber anything already in the config.
if command -v jq >/dev/null 2>&1; then
  _d=$(mktemp -d)
  printf '%s' '{"existingKey":"keep me","theme":"light","projects":{"/other":{"allowedTools":["Read"]}}}' > "$_d/.claude.json"
  # The folder key is deliberately NOT written like a unix path here. On Git Bash
  # under Windows, jq is a native binary, so an argument that looks like an
  # absolute unix path is rewritten on the way in ("/home/ai/hub" becomes
  # "C:/Program Files/Git/home/ai/hub"), and turning that rewriting off breaks the
  # filename argument instead. The function does not care about the format, so the
  # test uses a name MSYS leaves alone. On the Linux servers this runs on, real
  # paths are passed and nothing is rewritten.
  ( HOME="$_d"; KB_CLAUDE_BIN=/bin/echo; kb_skip_claude_first_run "TESTFOLDER" )
  _j() { jq -r "$1" "$_d/.claude.json"; }
  t "onboarding marked complete"            "$(_j '.hasCompletedOnboarding')"                      "true"
  t "the folder is pre-trusted"             "$(_j '.projects.TESTFOLDER.hasTrustDialogAccepted')"  "true"
  t "unrelated keys survive"                "$(_j '.existingKey')"                                 "keep me"
  t "another project's settings survive"    "$(_j '.projects["/other"].allowedTools[0]')"           "Read"
  t "an existing theme is not overwritten"  "$(_j '.theme')"                                       "light"
  rm -rf "$_d"

  # THE PERMISSION PROFILE. Without it the reader approves every file read, one
  # at a time, during their own install - the exact "on a server, ask-me-first
  # means no" trap the book teaches. An existing settings.json must survive.
  _p=$(mktemp -d); mkdir -p "$_p/.claude"
  printf '%s' '{"permissions":{"allow":["Read(**)"]},"mine":"do not lose this"}' > "$_p/.claude/settings.json"
  ( HOME="$_p"; kb_grant_working_permissions "settings/server-profile.json" ) >/dev/null 2>&1
  t "profile is installed"          "$(jq -r '.permissions.allow | index("Bash(*)") != null' "$_p/.claude/settings.json")" "true"
  # Claude Code REWRITES this file and drops it entirely if it carries keys
  # outside the published schema. That cost the whole profile once already.
  t "profile has only schema keys"  "$(jq -r 'keys | map(select(. != "$schema" and . != "permissions")) | length' "$_p/.claude/settings.json")" "0"
  t "the old settings are kept"     "$(jq -r '.mine' "$_p/.claude/settings.json.before-install")"                          "do not lose this"
  # a second run must not overwrite the backup with our own file
  ( HOME="$_p"; kb_grant_working_permissions "settings/server-profile.json" ) >/dev/null 2>&1
  t "a second run keeps the backup" "$(jq -r '.mine' "$_p/.claude/settings.json.before-install")"                          "do not lose this"
  rm -rf "$_p"
fi

# THE SHARED MEMORY LINK (join.sh). This is the wiring that makes one memory serve
# every machine, and every one of these cases is a way it could lose a memory
# instead. Nothing here may ever delete a file: the whole design exists so that a
# memory cannot be lost, and a test suite that does not check that is decoration.

# The path is DERIVED from the hub location, never typed. If this is wrong the
# assistant writes into a folder nobody syncs and everything looks fine.
t "the memory path is derived from the hub folder" \
  "$(HOME=/h kb_ai_memory_path '/home/ai/my hub')" "/h/.claude/projects/-home-ai-my-hub/memory"
t "a Windows-style path mangles the same way" \
  "$(HOME=/h kb_ai_memory_path 'C:\hub')" "/h/.claude/projects/c--hub/memory"

# Git Bash on Windows silently turns `ln -s` into a COPY. A copy passes a naive
# check and shares nothing, so rather than pretend, the link cases are skipped
# here and run for real on Linux (the VPS, and any reader's server).
_probe=$(mktemp -d); mkdir "$_probe/real"; ln -sfn "$_probe/real" "$_probe/link" 2>/dev/null
if [ -L "$_probe/link" ]; then
  _h=$(mktemp -d); _hub="$_h/hub"; mkdir -p "$_hub"

  ( HOME="$_h"; kb_link_ai_memory "$_hub" ) >/dev/null 2>&1
  _link="$_h/.claude/projects/$(printf '%s' "$_hub" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')/memory"
  t "a fresh machine gets the link"        "$([ -L "$_link" ] && echo yes)" "yes"
  t "the link points at the hub's memory"  "$(cd "$_link" && pwd -P)" "$(cd "$_hub/memory" && pwd -P)"
  t "an empty memory folder is not a mystery" "$([ -s "$_hub/memory/MEMORY.md" ] && echo yes)" "yes"

  # Twice must equal once, or re-running the installer is a thing people fear.
  printf 'a real memory\n' > "$_hub/memory/fact.md"
  ( HOME="$_h"; kb_link_ai_memory "$_hub" ) >/dev/null 2>&1
  t "running it again keeps the memories"  "$(cat "$_hub/memory/fact.md")" "a real memory"

  # A machine that already has memories in the OLD place. They must arrive in the
  # hub, and the old folder must survive: never delete what you cannot get back.
  _h2=$(mktemp -d); _hub2="$_h2/hub"; mkdir -p "$_hub2"
  _old="$_h2/.claude/projects/$(printf '%s' "$_hub2" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')/memory"
  mkdir -p "$_old"; printf 'learned before joining\n' > "$_old/older.md"
  ( HOME="$_h2"; kb_link_ai_memory "$_hub2" ) >/dev/null 2>&1
  t "memories from before the join are carried in" "$(cat "$_hub2/memory/older.md" 2>/dev/null)" "learned before joining"
  t "the old folder is kept, not deleted"          "$(ls -d "$_old".replaced-* >/dev/null 2>&1 && echo yes)" "yes"

  # THE ONE THAT LOOKS LIKE SUCCESS. A link left over from a hub at a different
  # path is still a link, so a check for "is it a link" reports everything fine
  # while the assistant writes into a folder nobody syncs any more.
  _h3=$(mktemp -d); _hub3="$_h3/hub"; _stale="$_h3/somewhere-else"; mkdir -p "$_hub3" "$_stale"
  _l3="$_h3/.claude/projects/$(printf '%s' "$_hub3" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')/memory"
  mkdir -p "$(dirname "$_l3")"; ln -sfn "$_stale" "$_l3"
  ( HOME="$_h3"; kb_link_ai_memory "$_hub3" ) >/dev/null 2>&1
  t "a link pointing at the wrong hub is repaired" "$(cd "$_l3" && pwd -P)" "$(cd "$_hub3/memory" && pwd -P)"

  rm -rf "$_h" "$_h2" "$_h3"
else
  echo "  skip  the memory-link cases (this shell cannot make symlinks; run on Linux)"
fi
rm -rf "$_probe"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
TEST
rc=$?

echo
[ "$rc" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$rc"
