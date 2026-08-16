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
         kb_ai_memory_path kb_seed_memory_index kb_link_ai_memory \
         kb_hub_looks_real kb_find_hub kb_update_hub kb_install_hub_cli \
         kb_os kb_can_sudo kb_note_missing kb_install_one kb_install_claude_code \
         kb_install_prereqs kb_copy_starter_hub kb_new_hub kb_install_prompt_harvest \
         kb_install_hub_tools kb_ai_tool_detected kb_ai_tool_info kb_detect_ai_tools \
         kb_enabled_sources kb_write_prompt_sources kb_sync_report \
         kb_age kb_age_keygen kb_have_age kb_hub_key_path kb_notebook_state \
         kb_unseal_hub_key kb_seal_hub_key kb_store_notebook_token kb_write_mcp_config \
         kb_install_notebook_sync kb_persist_notebook_env kb_connect_notebook; do
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

# These five assert what happens with NO terminal, so they must FORCE that state
# instead of assuming the machine has none.
#
# They used to assume it, and the assumption held only by luck. Git Bash on
# Windows has no terminal here, so the suite passed; WSL and any Mac or Linux
# terminal DOES have one, so `ask` resolved to /dev/tty and sat there forever
# waiting for an answer nobody was there to give. Found 2026-08-10, running the
# suite on real Linux for the first time. A test that hangs on half the machines
# it is meant to protect is not protecting them.
#
# Same override technique as resolve_with below, for the same reason: the two
# conditions are separate functions precisely so they can be faked.
no_tty() { ( kb_stdin_is_tty(){ false; }; kb_can_open_tty(){ false; }; KB_TTY=""; "$@" ) }

t "ask falls back to its default"      "$(no_tty ask 'Repo name' 'my-hub')" "my-hub"
t "ask with no default returns empty"  "$(no_tty ask 'Anything')"           ""
if no_tty ask_yes "Proceed" "y"; then t "ask_yes honours a y default" yes yes; else t "ask_yes honours a y default" no yes; fi
if no_tty ask_yes "Proceed" "n"; then t "ask_yes honours an n default" yes no; else t "ask_yes honours an n default" no no; fi
if no_tty have_tty; then t "have_tty is false with no terminal" true false; else t "have_tty is false with no terminal" false false; fi

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
# Forced headless, for the same reason as the ask cases above: this asserts what
# happens on a machine with NO terminal, and on one that HAS a terminal it takes a
# different and equally correct branch. Assuming instead of forcing is why this
# passed on Windows and failed on Linux.
out="$( ( kb_stdin_is_tty(){ false; }; kb_can_open_tty(){ false; }; KB_TTY=""
          KB_CLAUDE_BIN=/bin/true; ensure_claude_signin ) 2>&1 )"
case "$out" in *"no terminal"*) t "headless sign-in fails honestly" yes yes ;;
               *) t "headless sign-in fails honestly" "$out" yes ;; esac

# EXTRA DIRECTORIES. The step sheets the installer must follow live outside the
# folder Claude is started in, and Read(**) only covers that folder. They go into
# the settings file, NOT onto the command line: --add-dir takes a variable number
# of values, so a trailing prompt argument is swallowed as one more directory. On
# a live box that left Claude Code sitting at an empty prompt, doing nothing.
# A skip must SAY so. These blocks need jq, and when it is absent they used to
# vanish without a word: 12 cases silently not running, and the suite still
# printing ALL PASS. Found 2026-08-10 on Ubuntu, which ships no jq. A silent
# skip reads exactly like a pass, which is the one thing a test must never do.
if ! command -v jq >/dev/null 2>&1; then
  printf '  skip  the settings-file cases (no jq on this machine: apt-get install jq)\n'
else
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
if ! command -v jq >/dev/null 2>&1; then
  printf '  skip  the first-run and permission-profile cases (no jq on this machine)\n'
else
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

  # Detection is FORCED to "Claude Code is here" throughout this block, because the
  # link is gated on it now and these cases are about the link itself, not the gate.
  # The gate has its own cases further down.
  ( HOME="$_h"; KB_ASSUME_TOOLS=claude kb_link_ai_memory "$_hub" ) >/dev/null 2>&1
  _link="$_h/.claude/projects/$(printf '%s' "$_hub" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')/memory"
  t "a fresh machine gets the link"        "$([ -L "$_link" ] && echo yes)" "yes"
  t "the link points at the hub's memory"  "$(cd "$_link" && pwd -P)" "$(cd "$_hub/memory" && pwd -P)"
  t "an empty memory folder is not a mystery" "$([ -s "$_hub/memory/MEMORY.md" ] && echo yes)" "yes"

  # Twice must equal once, or re-running the installer is a thing people fear.
  printf 'a real memory\n' > "$_hub/memory/fact.md"
  ( HOME="$_h"; KB_ASSUME_TOOLS=claude kb_link_ai_memory "$_hub" ) >/dev/null 2>&1
  t "running it again keeps the memories"  "$(cat "$_hub/memory/fact.md")" "a real memory"

  # A machine that already has memories in the OLD place. They must arrive in the
  # hub, and the old folder must survive: never delete what you cannot get back.
  _h2=$(mktemp -d); _hub2="$_h2/hub"; mkdir -p "$_hub2"
  _old="$_h2/.claude/projects/$(printf '%s' "$_hub2" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')/memory"
  mkdir -p "$_old"; printf 'learned before joining\n' > "$_old/older.md"
  ( HOME="$_h2"; KB_ASSUME_TOOLS=claude kb_link_ai_memory "$_hub2" ) >/dev/null 2>&1
  t "memories from before the join are carried in" "$(cat "$_hub2/memory/older.md" 2>/dev/null)" "learned before joining"
  t "the old folder is kept, not deleted"          "$(ls -d "$_old".replaced-* >/dev/null 2>&1 && echo yes)" "yes"

  # THE ONE THAT LOOKS LIKE SUCCESS. A link left over from a hub at a different
  # path is still a link, so a check for "is it a link" reports everything fine
  # while the assistant writes into a folder nobody syncs any more.
  _h3=$(mktemp -d); _hub3="$_h3/hub"; _stale="$_h3/somewhere-else"; mkdir -p "$_hub3" "$_stale"
  _l3="$_h3/.claude/projects/$(printf '%s' "$_hub3" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')/memory"
  mkdir -p "$(dirname "$_l3")"; ln -sfn "$_stale" "$_l3"
  ( HOME="$_h3"; KB_ASSUME_TOOLS=claude kb_link_ai_memory "$_hub3" ) >/dev/null 2>&1
  t "a link pointing at the wrong hub is repaired" "$(cd "$_l3" && pwd -P)" "$(cd "$_hub3/memory" && pwd -P)"

  rm -rf "$_h" "$_h2" "$_h3"
else
  echo "  skip  the memory-link cases (this shell cannot make symlinks; run on Linux)"
fi
rm -rf "$_probe"

# --- WHICH AI TOOLS LIVE HERE, AND WHO SAID YES ------------------------------
# Added 2026-08-11. Before this the installer wired sync with no detection, no
# disclosure and no choice: it invented a ~/.claude folder on machines that had
# never seen Claude Code, and the harvest read Codex's logs and pushed them to
# the repository without a word. These are the bash twins of the cases in
# windows/test-windows.ps1. When you change one side, change both.
#
# Detection is FORCED (KB_ASSUME_TOOLS), never read from the machine running the
# suite, so the suite behaves the same on a machine crowded with AI tools and on
# a bare one.

t "an assumed tool is reported with its powers" \
  "$(KB_ASSUME_TOOLS=claude kb_detect_ai_tools)" "claude|memory+prompts|Claude Code|"
t "a machine with nothing reports nothing" \
  "$(KB_ASSUME_TOOLS=- kb_detect_ai_tools)" ""
t "an unsyncable tool is reported with its reason" \
  "$(KB_ASSUME_TOOLS=comet kb_detect_ai_tools | grep -c 'not in files here')" "1"

# Who decides, in order: the flag this run, the record on this device, detection.
_s=$(mktemp -d)
t "no flag and no record means every syncable tool found" \
  "$(HOME="$_s" KB_ASSUME_TOOLS=claude,codex,comet kb_enabled_sources)" "claude,codex"
mkdir -p "$_s/.hub"; printf 'HUB_PROMPT_SOURCES=claude\n' > "$_s/.hub/device.env"
t "the choice recorded on the device wins over detection" \
  "$(HOME="$_s" KB_ASSUME_TOOLS=claude,codex kb_enabled_sources)" "claude"
t "the flag this run wins over the record" \
  "$(HOME="$_s" KB_ASSUME_TOOLS=claude,codex KB_SYNC_SOURCES=codex kb_enabled_sources)" "codex"
t "an empty flag means none, not everything" \
  "$(HOME="$_s" KB_ASSUME_TOOLS=claude,codex KB_SYNC_SOURCES= kb_enabled_sources)" ""
t "dash is none, spelled so Windows can say it" \
  "$(HOME="$_s" KB_ASSUME_TOOLS=claude,codex KB_SYNC_SOURCES=- kb_enabled_sources)" ""

# Recording the choice must replace, never stack, and never eat neighbours.
_s2=$(mktemp -d); mkdir -p "$_s2/.hub"
printf 'HUB_DIR=/somewhere\n' > "$_s2/.hub/device.env"
( HOME="$_s2" kb_write_prompt_sources "claude,codex" ) >/dev/null 2>&1
t "the choice is recorded on the device" \
  "$(grep -c '^HUB_PROMPT_SOURCES=claude,codex$' "$_s2/.hub/device.env")" "1"
( HOME="$_s2" kb_write_prompt_sources "claude" ) >/dev/null 2>&1
t "a new choice replaces the old one" \
  "$(grep -c '^HUB_PROMPT_SOURCES=' "$_s2/.hub/device.env")" "1"
t "and what else the file held survives" \
  "$(grep -c '^HUB_DIR=/somewhere$' "$_s2/.hub/device.env")" "1"

# The report is the disclosure. It must name each state in plain words.
_rep="$(HOME="$_s2" KB_ASSUME_TOOLS=claude,codex,comet KB_SYNC_SOURCES=claude kb_sync_report)"
t "the report says what is synced"           "$(printf '%s' "$_rep" | grep -c 'Claude Code: its memory folder')" "1"
t "the report says what was left alone"      "$(printf '%s' "$_rep" | grep -c 'Codex (switched off by your choice')" "1"
t "the report says what cannot be synced"    "$(printf '%s' "$_rep" | grep -c 'Perplexity Comet:')" "1"
t "a machine syncing nothing is told so" \
  "$(KB_ASSUME_TOOLS=- KB_SYNC_SOURCES= kb_sync_report | grep -c 'Nothing is synced')" "1"

# THE GATE ON THE MEMORY LINK. No Claude Code, no link, and above all no invented
# ~/.claude folder on a machine that never had one.
_g=$(mktemp -d); _ghub="$_g/hub"; mkdir -p "$_ghub"
( HOME="$_g"; KB_ASSUME_TOOLS=- kb_link_ai_memory "$_ghub" ) >/dev/null 2>&1
t "no Claude Code means no invented ~/.claude" \
  "$([ -e "$_g/.claude" ] && echo yes || echo no)" "no"
t "but the hub still gets its memory index" \
  "$([ -s "$_ghub/memory/MEMORY.md" ] && echo yes)" "yes"
_g2=$(mktemp -d); _ghub2="$_g2/hub"; mkdir -p "$_ghub2"
( HOME="$_g2"; KB_ASSUME_TOOLS=claude KB_SYNC_SOURCES=codex kb_link_ai_memory "$_ghub2" ) >/dev/null 2>&1
t "Claude Code switched off means its folder is left alone" \
  "$([ -e "$_g2/.claude" ] && echo yes || echo no)" "no"
rm -rf "$_s" "$_s2" "$_g" "$_g2"

# FINDING A HUB THAT IS ALREADY INSTALLED, AND WIRING ITS COMMANDS.
# Added 2026-08-09 after `hub map` on the work PC answered with a path from the
# rented server. Two holes: the tool did not know which copy it was reading, and
# there was no `hub` command on that machine at all. This half is the second hole.

_f=$(mktemp -d)
_home0="${HOME:-}"
mkdir -p "$_f/notahub" "$_f/hub/.git" "$_f/hub/memory" "$_f/hub/agents/hub-cli"
t "a folder that is not a hub is refused"  "$(kb_hub_looks_real "$_f/notahub" && echo yes || echo no)" "no"
t "a real hub is recognised"               "$(kb_hub_looks_real "$_f/hub" && echo yes || echo no)"     "yes"
t "a folder that does not exist is refused" "$(kb_hub_looks_real "$_f/nope" && echo yes || echo no)"   "no"
t "the hint is used when it is a real hub" "$(HOME="$_f" kb_find_hub "$_f/hub")" "$(cd "$_f/hub" && pwd -P)"
# A wrong hint must never be handed back as if it were right. It has to keep looking,
# so the check is "did NOT return the bad path", not "returned nothing" - this machine
# may well have a real hub at C:\hub for it to find instead, and that is a fine answer.
_bad="$(HOME="$_f" HUB_DIR= HUB= kb_find_hub "$_f/notahub")"
t "a hint that is not a hub is not trusted" "$([ "$_bad" = "$_f/notahub" ] && echo trusted || echo no)" "no"

# "Nothing found" only means anything on a machine that genuinely has no hub in any
# of the usual homes. On Michael's own machines one is always there, so this case
# skips itself rather than failing for the wrong reason.
_empty=$(mktemp -d)
if HOME="$_empty" HUB_DIR= HUB= kb_find_hub >/dev/null 2>&1; then
  echo "  skip  the no-hub-anywhere case (this machine has a hub in a usual place)"
else
  t "no hub anywhere fails, it does not guess" \
    "$(HOME="$_empty" HUB_DIR= HUB= kb_find_hub || echo NOTFOUND)" "NOTFOUND"
fi
rm -rf "$_empty"

# THE ONE THAT MATTERS. `hub memory search` is a wrapper that runs
# `hub-memory-lookup` by bare name. Wiring only `hub` gives a command that exists
# and then fails, which is worse than no command at all.
printf '#!/bin/sh\necho hub\n'      > "$_f/hub/agents/hub-cli/hub"
printf '#!/bin/sh\necho lookup\n'   > "$_f/hub/agents/hub-cli/hub-memory-lookup"
printf 'MODEL=x\n'                  > "$_f/hub/agents/hub-cli/models.env"
( HOME="$_f" kb_install_hub_cli "$_f/hub" ) >/dev/null 2>&1
t "the hub command is wired"          "$([ -e "$_f/.local/bin/hub" ] && echo yes)"               "yes"
t "the sibling tools are wired too"   "$([ -e "$_f/.local/bin/hub-memory-lookup" ] && echo yes)" "yes"
t "a config file is not wired as a command" "$([ -e "$_f/.local/bin/models.env" ] && echo yes || echo no)" "no"
# A hub with no tools is every reader's hub. It must not warn or half-wire.
mkdir -p "$_f/bare/.git" "$_f/bare/memory"
( HOME="$_f" kb_install_hub_cli "$_f/bare" ) >/dev/null 2>&1
t "a hub that ships no tools stays quiet" "$(HOME="$_f" kb_install_hub_cli "$_f/bare" 2>&1)" ""
# Not a git folder: say so and carry on, never abort the whole install.
t "updating a non-git folder is not fatal" \
  "$(HOME="$_f" kb_update_hub "$_f/notahub" >/dev/null 2>&1; echo $?)" "0"

# --- THE DAILY JOB THAT FILES WHAT YOU TYPE TO AN AI -------------------------
# Added 2026-08-10. The hub keeps a drawer of everything its owner has typed to an
# assistant, and filling it needs a job on each machine. Nothing installed that job:
# one computer had one because somebody typed it into that computer's schedule by
# hand, and every other computer quietly kept nothing. These are the bash twins of
# the cases in windows/test-windows.ps1. When you change one side, change both.
#
# A fake crontab, so the suite never edits the schedule of whoever is running it.
_cronfile="$_f/crontab.txt"; : > "$_cronfile"
cat > "$_f/fakecrontab" <<FAKE
#!/bin/sh
case "\$1" in
  -l) cat "$_cronfile" ;;
  -)  cat > "$_cronfile" ;;
esac
FAKE
chmod +x "$_f/fakecrontab"
export PATH="$_f:$PATH"

# A hub that ships no harvester is every reader's hub. Nothing to schedule, nothing said.
t "a hub with no harvester stays quiet" \
  "$(HOME="$_f" KB_CRONTAB="$_f/fakecrontab" kb_install_prompt_harvest "$_f/bare" 2>&1)" ""
t "and it schedules nothing" "$([ -s "$_cronfile" ] && echo yes || echo no)" "no"

mkdir -p "$_f/hub/bin"
printf 'console.log(1)\n' > "$_f/hub/bin/prompt-harvest.js"
( HOME="$_f" KB_CRONTAB="$_f/fakecrontab" kb_install_prompt_harvest "$_f/hub" ) >/dev/null 2>&1
t "a hub with a harvester gets a daily job" \
  "$(grep -c 'prompt-harvest.js' "$_cronfile")" "1"
t "the job is told not to work twice in one day" \
  "$(grep -c ' --once-a-day' "$_cronfile")" "1"

# Running the installer again is a normal thing to do. It must not stack up jobs.
printf 'BEFORE=keep\n' >> "$_cronfile"
( HOME="$_f" KB_CRONTAB="$_f/fakecrontab" kb_install_prompt_harvest "$_f/hub" ) >/dev/null 2>&1
t "a second run does not add a second job" \
  "$(grep -c 'prompt-harvest.js' "$_cronfile")" "1"
t "and it keeps what was already in the schedule" \
  "$(grep -c 'BEFORE=keep' "$_cronfile")" "1"

# A machine already carrying the server's hand-written line is already covered, whatever
# shape that line has. Recognise it instead of writing a second one beside it.
printf '20 4 * * * /root/hub/routines/prompt-harvest.sh\n' > "$_cronfile"
( HOME="$_f" KB_CRONTAB="$_f/fakecrontab" kb_install_prompt_harvest "$_f/hub" ) >/dev/null 2>&1
t "an existing hand-written job is left alone" "$(wc -l < "$_cronfile" | tr -d ' ')" "1"

# --- THE PROGRAMS THEMSELVES, INSTALLED ON THE MACHINE -----------------------
# Added 2026-08-10. The collector used to exist in exactly one person's own hub, so the
# program the book promises its readers ("a program fills it") was nowhere they could get
# it. It lives in the kit now and is installed ON THE MACHINE, never copied into the hub
# folder, because Chapter 4 promises the hub is a folder of text files and that nothing in
# it needs a terminal. These are the bash twins of the cases in windows/test-windows.ps1.
# When you change one side, change both.
_kit="$_f/kit"; mkdir -p "$_kit/tools" "$_f/hub2/memory"
printf 'console.log(1)\n'                    > "$_kit/tools/prompt-harvest.js"
printf '#!/usr/bin/env python3\nprint(1)\n'  > "$_kit/tools/hub-prompt-archive"
printf '# not a program\n'                   > "$_kit/tools/README.md"
git -C "$_kit" init -q >/dev/null 2>&1
git -C "$_kit" add -A >/dev/null 2>&1
git -C "$_kit" -c user.email=t@t -c user.name=t commit -qm tools >/dev/null 2>&1

# No kit named: nothing to fetch, nothing said. That is every other product using this file.
t "no kit named means nothing installed and nothing said" \
  "$(HOME="$_f" kb_install_hub_tools "$_f/hub2" "" 2>&1)" ""

( HOME="$_f" kb_install_hub_tools "$_f/hub2" "$_kit" ) >/dev/null 2>&1
t "the collector is installed on the machine" \
  "$([ -f "$_f/.local/bin/hub-prompt-archive" ] && echo yes || echo no)" "yes"
t "the runner is installed beside it, which is how it finds it" \
  "$([ -f "$_f/.local/bin/prompt-harvest.js" ] && echo yes || echo no)" "yes"
t "there is one command that starts it" \
  "$([ -x "$_f/.local/bin/hub-prompt-harvest" ] && echo yes || echo no)" "yes"
t "a README is not installed as a program" \
  "$([ -e "$_f/.local/bin/README.md" ] && echo yes || echo no)" "no"

# THE ONE THAT MATTERS. Chapter 4 promises the hub is a folder of text files. A Node program
# and a Python program appearing in it would be the first two things in there that are not.
# A hub of its own, because the scheduling cases above deliberately put a harvester in $_f/hub.
t "nothing was put inside the hub folder" \
  "$(find "$_f/hub2" \( -name 'hub-prompt-archive' -o -name 'prompt-harvest.js' \) 2>/dev/null | grep -c .)" "0"

# A job started by the schedule gets almost no environment, so where the hub is must be
# written down rather than guessed at.
t "where the hub is was written down for the scheduled job" \
  "$(grep -c "^HUB_DIR=" "$_f/.hub/device.env" 2>/dev/null)" "1"
t "and a second run does not write it twice" \
  "$(HOME="$_f" kb_install_hub_tools "$_f/hub2" "$_kit" >/dev/null 2>&1; grep -c '^HUB_DIR=' "$_f/.hub/device.env")" "1"

# THE ONE THAT BIT US ON THE FIRST LIVE RUN. kb_install_hub_cli puts SYMLINKS in this same
# folder, pointing back into the hub. `cp` over a symlink writes THROUGH it, so installing a
# program whose name matches one of those links overwrote a file inside the hub itself, and
# the only sign was a git folder that had changed on its own. Both suites had passed, because
# neither had ever put a link in the way first.
printf 'the hub owns this file\n' > "$_f/hub2/decoy"
rm -f "$_f/.local/bin/hub-prompt-archive"
ln -s "$_f/hub2/decoy" "$_f/.local/bin/hub-prompt-archive" 2>/dev/null
if [ -L "$_f/.local/bin/hub-prompt-archive" ]; then
  ( HOME="$_f" kb_install_hub_tools "$_f/hub2" "$_kit" ) >/dev/null 2>&1
  t "a link in the way is replaced, never written through" \
    "$(cat "$_f/hub2/decoy")" "the hub owns this file"
else
  # Loud, not silent. Git Bash on Windows makes a copy instead of a link unless it is told
  # otherwise, so this case cannot run here and must SAY it did not. A skip that reads like
  # a pass is the jq lesson further up this file, and this is exactly the case that lets a
  # real bug through: the live run that overwrote a hub file happened on Linux.
  printf '  skip  the symlink case (this shell cannot make one: run this suite on Linux too)\n'
fi

# With the programs on the machine, the schedule must run THOSE, not a copy inside a hub.
: > "$_cronfile"
( HOME="$_f" KB_CRONTAB="$_f/fakecrontab" kb_install_prompt_harvest "$_f/hub2" ) >/dev/null 2>&1
t "the schedule runs the installed program, not one inside the hub" \
  "$(grep -c 'hub-prompt-harvest' "$_cronfile")" "1"

# --- THE CREATE PATH ---------------------------------------------------------
# Added 2026-08-09 (D-105). For one day Windows could make a hub from nothing and
# this side could not, so a Mac reader on a fresh machine got an error while a
# Windows reader got a finished setup. These are the bash twins of the cases in
# windows/test-windows.ps1. When you change one side, change both.
#
# No network here, per the promise at the top of this file: the starter is a local
# git repo made on the spot, which tests the same code path a real one would.
_c="$(mktemp -d)"
_starter="$_c/product"
mkdir -p "$_starter/starter-hub/context" "$_starter/starter-hub/skills"
printf '# the real one\n' > "$_starter/starter-hub/AGENTS.md"
printf 'about\n'          > "$_starter/starter-hub/context/about-me.md"
printf 'plan\n'           > "$_starter/starter-hub/skills/plan-my-day.md"
( cd "$_starter" && git init -q . && git add -A && \
  git -c user.email=t@t -c user.name=t commit -q -m starter ) >/dev/null 2>&1

( HOME="$_c" kb_new_hub "$_c/made" "" "$_starter" ) >/dev/null 2>&1
t "a new hub gets the product starter files" \
  "$([ -f "$_c/made/context/about-me.md" ] && [ -f "$_c/made/skills/plan-my-day.md" ] && echo yes)" "yes"
t "the starter's own AGENTS.md is used, never an invented one" \
  "$(head -1 "$_c/made/AGENTS.md" 2>/dev/null)" "# the real one"
t "a new hub is a real hub afterwards" \
  "$(kb_hub_looks_real "$_c/made" && echo yes)" "yes"

# Running it twice must not tread on a sentence they have written about themselves.
printf '# mine, edited\n' > "$_c/made/AGENTS.md"
( HOME="$_c" kb_new_hub "$_c/made" "" "$_starter" ) >/dev/null 2>&1
t "a second run keeps what they have written" \
  "$(head -1 "$_c/made/AGENTS.md")" "# mine, edited"

# The product ships its own memory index; a blank one must not replace it.
mkdir -p "$_starter/starter-hub/memory"
printf '# Memory index - the product wrote this\n' > "$_starter/starter-hub/memory/MEMORY.md"
( cd "$_starter" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m mem ) >/dev/null 2>&1
( HOME="$_c" kb_new_hub "$_c/kept" "" "$_starter" ) >/dev/null 2>&1
t "the starter's memory index survives" \
  "$(head -1 "$_c/kept/memory/MEMORY.md" 2>/dev/null)" "# Memory index - the product wrote this"

# A folder with somebody's holiday photos in it is not a hub and must be refused.
mkdir -p "$_c/occupied"; printf 'x\n' > "$_c/occupied/holiday.jpg"
t "a folder with other files in it is refused" \
  "$(HOME="$_c" kb_new_hub "$_c/occupied" "" "$_starter" >/dev/null 2>&1; echo $?)" "1"

# An unreachable starter still leaves a working hub, and says so.
( HOME="$_c" kb_new_hub "$_c/nostarter" "" "$_c/does-not-exist" ) >/dev/null 2>&1
t "an unreachable starter still leaves a usable hub" \
  "$(kb_hub_looks_real "$_c/nostarter" && echo yes)" "yes"
t "and it warns rather than pretending it worked" \
  "$(HOME="$_c" kb_new_hub "$_c/nostarter2" "" "$_c/does-not-exist" 2>&1 | grep -c 'does NOT have the files')" "1"

# Cloning a hub they already keep somewhere.
( HOME="$_c" kb_new_hub "$_c/cloned" "$_starter" ) >/dev/null 2>&1
t "an existing hub is cloned from its address" \
  "$([ -d "$_c/cloned/.git" ] && [ -f "$_c/cloned/starter-hub/AGENTS.md" ] && echo yes)" "yes"
t "an address that is not a repository fails cleanly" \
  "$(HOME="$_c" kb_new_hub "$_c/bad" "$_c/ghost" >/dev/null 2>&1; echo $?)" "1"

# A brand new hub has no remote. Saying "could not pull, you may be out of date"
# is alarming and untrue - there is nowhere to be out of date FROM.
t "a hub with no remote is not called out of date" \
  "$(HOME="$_c" kb_update_hub "$_c/made" 2>&1 | grep -c 'could not pull')" "0"
t "it says the useful thing instead" \
  "$(HOME="$_c" kb_update_hub "$_c/made" 2>&1 | grep -c 'lives only on this computer')" "1"

# OS detection must answer something we actually branch on.
case "$(kb_os)" in
  macos|linux-apt|linux-other|other) t "kb_os names a system we handle" yes yes ;;
  *) t "kb_os names a system we handle" "$(kb_os)" "one of macos/linux-apt/linux-other/other" ;;
esac
# An already-present tool must short-circuit and never reach a package manager.
t "an already-present tool is not reinstalled" \
  "$(kb_install_one bash definitely-not-a-package definitely-not-a-package Bash >/dev/null 2>&1; echo $?)" "0"
rm -rf "$_c"


# --- YOUR NOTEBOOK: CONNECTING IT ONCE, AND THE CONNECTION TRAVELLING ---------
# Added 2026-08-16. The installer had no credential step at all before this, and a
# reader-facing step with no test is how the invisible backspace byte survived. These
# are the bash twins of the cases in windows/test-windows.ps1. Change one, change both.
_n=$(mktemp -d)
mkdir -p "$_n/home/.hub" "$_n/hub/secrets" "$_n/home/.local/bin"
HOME="$_n/home"; export HOME

t "a hub with no notebook reports 'none'" "$(kb_notebook_state "$_n/hub")" "none"
: > "$_n/hub/secrets/hub-key.age"
t "a folder carrying a sealed key reports 'sealed'" "$(kb_notebook_state "$_n/hub")" "sealed"
rm -f "$_n/hub/secrets/hub-key.age"

# Refusals first, because they are what a reader hits at the worst moment.
t "unsealing does nothing when the folder carries no key" \
  "$(kb_unseal_hub_key "$_n/hub" >/dev/null 2>&1; echo $?)" "1"
t "sealing does nothing when this computer has no key" \
  "$(kb_seal_hub_key "$_n/hub" >/dev/null 2>&1; echo $?)" "1"
t "and neither of those left a file behind" \
  "$([ -e "$_n/hub/secrets/hub-key.age" ] && echo yes || echo no)" "no"
: > "$_n/home/.hub/age-key.txt"
: > "$_n/hub/secrets/hub-key.age"
t "unsealing is a no-op when this computer already has a key" \
  "$(kb_unseal_hub_key "$_n/hub" >/dev/null 2>&1; echo $?)" "0"
rm -f "$_n/home/.hub/age-key.txt" "$_n/hub/secrets/hub-key.age"

# The file that tells the assistant where the notebook is.
kb_write_mcp_config "$_n/hub" >/dev/null 2>&1
t "the assistant is given an .mcp.json" "$([ -f "$_n/hub/.mcp.json" ] && echo yes || echo no)" "yes"
t "the connection NAMES the credential rather than carrying one" \
  "$(grep -c 'Bearer \${MENERIO_MCP_TOKEN}' "$_n/hub/.mcp.json")" "1"
t "and it is valid JSON, which is the only way an assistant will read it" \
  "$(python3 -c 'import json,sys;json.load(open(sys.argv[1]));print("ok")' "$_n/hub/.mcp.json" 2>/dev/null)" "ok"
printf 'mine\n' > "$_n/hub/.mcp.json"
kb_write_mcp_config "$_n/hub" >/dev/null 2>&1
t "a reader's own .mcp.json is never overwritten" "$(cat "$_n/hub/.mcp.json")" "mine"
rm -f "$_n/hub/.mcp.json"

# The sync: on save, and hourly. Both must be silent for a reader with no notebook,
# which is why they are installed for everyone.
_cronfile2="$_n/crontab.txt"; : > "$_cronfile2"
cat > "$_n/fakecrontab" <<FAKE
#!/bin/sh
case "\$1" in
  -l) cat "$_cronfile2" ;;
  -)  cat > "$_cronfile2" ;;
esac
FAKE
chmod +x "$_n/fakecrontab"
t "no sync program on this computer means nothing is scheduled and nothing is said" \
  "$(KB_CRONTAB="$_n/fakecrontab" kb_install_notebook_sync "$_n/hub" 2>&1)" ""
printf '#!/bin/sh\nexit 0\n' > "$_n/home/.local/bin/hub-notebook-sync"
chmod +x "$_n/home/.local/bin/hub-notebook-sync"
git -C "$_n/hub" init -q 2>/dev/null
( KB_CRONTAB="$_n/fakecrontab" kb_install_notebook_sync "$_n/hub" ) >/dev/null 2>&1
t "a change that is saved updates the notebook" \
  "$(grep -c 'hub-notebook-sync' "$_n/hub/.git/hooks/post-commit" 2>/dev/null)" "1"
t "and the hook can never fail the save" \
  "$(grep -c '^exit 0' "$_n/hub/.git/hooks/post-commit" 2>/dev/null)" "1"
t "there is an hourly catch-up for what happened while the computer slept" \
  "$(grep -c 'hub-notebook-sync' "$_cronfile2")" "1"
printf 'BEFORE=keep\n' >> "$_cronfile2"
( KB_CRONTAB="$_n/fakecrontab" kb_install_notebook_sync "$_n/hub" ) >/dev/null 2>&1
t "running the installer twice does not stack up two jobs" \
  "$(grep -c 'hub-notebook-sync' "$_cronfile2")" "1"
t "and it keeps what was already in the schedule" "$(grep -c 'BEFORE=keep' "$_cronfile2")" "1"
printf '#!/bin/sh\n# someone elses hook\n' > "$_n/hub/.git/hooks/post-commit"
( KB_CRONTAB="$_n/fakecrontab" kb_install_notebook_sync "$_n/hub" ) >/dev/null 2>&1
t "a hook the reader wrote themselves is left exactly as it was" \
  "$(grep -c 'someone elses hook' "$_n/hub/.git/hooks/post-commit")" "1"

# The shell start-up line that supplies the value .mcp.json only names.
printf '#!/bin/sh\nexit 0\n' > "$_n/home/.local/bin/hub-notebook-env"
: > "$_n/home/.bashrc"
kb_persist_notebook_env "$_n/hub" >/dev/null 2>&1
t "new terminals are told where the credential comes from" \
  "$(grep -c 'hub-notebook-env' "$_n/home/.bashrc")" "1"
kb_persist_notebook_env "$_n/hub" >/dev/null 2>&1
t "and running it twice does not write the line twice" \
  "$(grep -c 'hub-notebook-env' "$_n/home/.bashrc")" "1"

# Saying no has to be free, because a hub built from the book has no notebook and
# needs none. This is the case that must never nag.
t "a reader who says no is not asked again and nothing is written" \
  "$(KB_NOTEBOOK=skip kb_connect_notebook "$_n/hub" 2>&1)" ""

# The real round trip, where age is installed. It is the mechanism the whole promise
# rests on, so it is proven rather than assumed - and skipped OUT LOUD where it cannot be.
if command -v age >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1; then
  rm -f "$_n/home/.hub/age-key.txt" "$_n/hub/secrets/hub-secrets.env.age"
  ( kb_store_notebook_token "$_n/hub" "test-token-not-a-real-one-0123456789" ) >/dev/null 2>&1
  t "pasting a token makes a key and locks the token inside the folder" \
    "$([ -f "$_n/hub/secrets/hub-secrets.env.age" ] && [ -r "$_n/home/.hub/age-key.txt" ] && echo yes || echo no)" "yes"
  t "the folder now reports itself connected on this computer" \
    "$(kb_notebook_state "$_n/hub")" "connected"
  t "the token can be read back out, exactly as it was pasted" \
    "$(age -d -i "$_n/home/.hub/age-key.txt" "$_n/hub/secrets/hub-secrets.env.age" | sed -n 's/^MENERIO_MCP_TOKEN=//p')" \
    "test-token-not-a-real-one-0123456789"
  t "one paste answers both programs that need it" \
    "$(age -d -i "$_n/home/.hub/age-key.txt" "$_n/hub/secrets/hub-secrets.env.age" | grep -c '^MENERIO_')" "2"
  ( kb_store_notebook_token "$_n/hub" "second-token-still-not-real-98765" ) >/dev/null 2>&1
  t "connecting again replaces the credential instead of keeping two" \
    "$(age -d -i "$_n/home/.hub/age-key.txt" "$_n/hub/secrets/hub-secrets.env.age" | grep -c '^MENERIO_MCP_TOKEN=')" "1"
  # A key that opens nothing must never be sealed: the machine that would find out is
  # the new one, at the moment it has no other way in.
  age-keygen -o "$_n/home/.hub/age-key.txt" 2>/dev/null
  t "a key that does not open the folder's credentials is refused, not sealed" \
    "$(kb_seal_hub_key "$_n/hub" >/dev/null 2>&1; echo $?)" "1"
  t "and that refusal left no sealed key behind" \
    "$([ -e "$_n/hub/secrets/hub-key.age" ] && echo yes || echo no)" "no"
else
  echo "  skip  the real lock-and-unlock round trip (age is not on this computer)"
fi
HOME="$_home0"; export HOME
rm -rf "$_n"

rm -rf "$_f"

echo
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
TEST
rc=$?

# Bytes, not appearance. join.ps1 carried a literal backspace where the backslash-b of
# '.local\bin' belonged, so the path could never exist and every Windows reader silently got
# no prompt archive. It reads correctly on screen and matches neither obvious grep.
echo
echo "== no hidden control characters"
bash test-no-control-characters.sh || rc=1

echo
[ "$rc" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$rc"
