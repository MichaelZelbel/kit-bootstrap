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
         kb_hub_looks_real kb_find_hub kb_update_hub kb_install_hub_cli kb_record_hub_dir \
         kb_default_hub_dir kb_cloud_synced_parents kb_physical_path kb_refuse_hub_path \
         kb_os kb_can_sudo kb_note_missing kb_install_one kb_install_claude_code \
         kb_install_hermes \
         kb_install_prereqs kb_copy_starter_hub kb_new_hub kb_install_prompt_harvest \
         kb_install_hub_tools kb_ai_tool_detected kb_ai_tool_info kb_detect_ai_tools \
         kb_enabled_sources kb_write_prompt_sources kb_sync_report \
         kb_age kb_age_keygen kb_have_age kb_hub_key_path kb_notebook_state \
         kb_unseal_hub_key kb_seal_hub_key kb_store_notebook_token kb_write_mcp_config \
         kb_install_notebook_sync kb_persist_notebook_env kb_connect_notebook \
         kb_seed_expiry_record kb_seed_due_folder \
         kb_json_str kb_count_recipes kb_skills_room kb_point_at_room \
         kb_hermes_skills_dir kb_wire_skills kb_hermes_bin kb_hermes_here \
         kb_hermes_has_credential kb_hermes_reads_hub kb_point_hermes_at_hub \
         kb_hermes_deny_rules kb_hermes_approvals kb_hermes_approvals_selfcheck \
         kb_gateway_state kb_install_gateway kb_cron_has_job kb_cron_job \
         kb_hermes_signin kb_hermes_has_provider kb_room_twin; do
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
  t "the link points at the hub's observations" "$(cd "$_link" && pwd -P)" "$(cd "$_hub/observations" && pwd -P)"
  t "an empty observations folder is not a mystery" "$([ -s "$_hub/observations/MEMORY.md" ] && echo yes)" "yes"
  # The page must be a doorplate, not a rules list: rules belong in AGENTS.md, and a page that
  # starts collecting them is how the always-read layer grew to 16,000 characters in the hub.
  t "the page sends rules to AGENTS.md instead of holding them" \
    "$(grep -qi 'AGENTS.md' "$_hub/observations/MEMORY.md" && echo yes)" "yes"

  # Twice must equal once, or re-running the installer is a thing people fear.
  printf 'a real memory\n' > "$_hub/observations/fact.md"
  ( HOME="$_h"; KB_ASSUME_TOOLS=claude kb_link_ai_memory "$_hub" ) >/dev/null 2>&1
  t "running it again keeps the memories"  "$(cat "$_hub/observations/fact.md")" "a real memory"

  # A machine that already has memories in the OLD place. They must arrive in the
  # hub, and the old folder must survive: never delete what you cannot get back.
  _h2=$(mktemp -d); _hub2="$_h2/hub"; mkdir -p "$_hub2"
  _old="$_h2/.claude/projects/$(printf '%s' "$_hub2" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')/memory"
  mkdir -p "$_old"; printf 'learned before joining\n' > "$_old/older.md"
  ( HOME="$_h2"; KB_ASSUME_TOOLS=claude kb_link_ai_memory "$_hub2" ) >/dev/null 2>&1
  t "memories from before the join are carried in" "$(cat "$_hub2/observations/older.md" 2>/dev/null)" "learned before joining"
  t "the old folder is kept, not deleted"          "$(ls -d "$_old".replaced-* >/dev/null 2>&1 && echo yes)" "yes"

  # THE ONE THAT LOOKS LIKE SUCCESS. A link left over from a hub at a different
  # path is still a link, so a check for "is it a link" reports everything fine
  # while the assistant writes into a folder nobody syncs any more.
  _h3=$(mktemp -d); _hub3="$_h3/hub"; _stale="$_h3/somewhere-else"; mkdir -p "$_hub3" "$_stale"
  _l3="$_h3/.claude/projects/$(printf '%s' "$_hub3" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')/memory"
  mkdir -p "$(dirname "$_l3")"; ln -sfn "$_stale" "$_l3"
  ( HOME="$_h3"; KB_ASSUME_TOOLS=claude kb_link_ai_memory "$_hub3" ) >/dev/null 2>&1
  t "a link pointing at the wrong hub is repaired" "$(cd "$_l3" && pwd -P)" "$(cd "$_hub3/observations" && pwd -P)"

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
t "but the hub still gets its memory page" \
  "$([ -s "$_ghub/observations/MEMORY.md" ] && echo yes)" "yes"
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

# A job written for a hub that has since moved names a folder that is gone. It is
# re-pointed, not kept beside a second one (D-179, 2026-09-02). The runner form carries
# no folder at all, so only the hub's-own-copy form can go stale.
mkdir -p "$_f/elsewhere/bin"; printf 'console.log(1)\n' > "$_f/elsewhere/bin/prompt-harvest.js"
printf '17 * * * * "/usr/bin/node" "%s/hub/bin/prompt-harvest.js" --once-a-day\n' "$_f" > "$_cronfile"
( HOME="$_f" KB_CRONTAB="$_f/fakecrontab" kb_install_prompt_harvest "$_f/elsewhere" ) >/dev/null 2>&1
t "a job for a hub that moved is re-pointed at this hub" "$(grep -c "$_f/elsewhere/bin/prompt-harvest.js" "$_cronfile")" "1"
t "and the old line is gone, not kept beside it"        "$(grep -c "$_f/hub/bin/prompt-harvest.js" "$_cronfile")" "0"
# device.env is how the daily jobs find the hub, so a re-run corrects it too.
mkdir -p "$_f/.hub"
printf 'HUB_DIR=%s/hub\nHUB_PROMPT_SOURCES=claude\n' "$_f" > "$_f/.hub/device.env"
( HOME="$_f" kb_record_hub_dir "$_f/elsewhere" ) >/dev/null 2>&1
t "device.env is re-pointed when HUB_DIR names another folder" "$(sed -n 's/^HUB_DIR=//p' "$_f/.hub/device.env")" "$_f/elsewhere"
t "and the other lines in it are kept"                         "$(grep -c '^HUB_PROMPT_SOURCES=claude' "$_f/.hub/device.env")" "1"
( HOME="$_f" kb_record_hub_dir "$_f/elsewhere" ) >/dev/null 2>&1
t "a second run with the same hub changes nothing"            "$(grep -c '^HUB_DIR=' "$_f/.hub/device.env")" "1"

# --- THE PROGRAMS THEMSELVES, INSTALLED ON THE MACHINE -----------------------
# Added 2026-08-10. The collector used to exist in exactly one person's own hub, so the
# program the book promises its readers ("a program fills it") was nowhere they could get
# it. It lives in the kit now and is installed ON THE MACHINE, never copied into the hub
# folder, because Chapter 4 promises the hub is a folder of text files and that nothing in
# it needs a terminal. These are the bash twins of the cases in windows/test-windows.ps1.
# When you change one side, change both.
_kit="$_f/kit"; mkdir -p "$_kit/tools" "$_f/hub2/memory"
printf 'console.log(1)\n'                    > "$_kit/tools/prompt-harvest.js"
printf 'console.log(1)\n'                    > "$_kit/tools/compile-rules.js"
printf '#!/usr/bin/env python3\nprint(1)\n'  > "$_kit/tools/hub-prompt-archive"
printf '#!/bin/sh\nexit 0\n'                 > "$_kit/tools/hub-notebook-sync"
printf '#!/bin/sh\nexit 0\n'                 > "$_kit/tools/hub-notebook-env"
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
# The rules compiler is the one program in here a reader types by hand, and until
# 2026-08-21 it was Python and the book named a path inside the hub that nobody has.
t "the rules compiler is installed on the machine" \
  "$([ -f "$_f/.local/bin/compile-rules.js" ] && echo yes || echo no)" "yes"
t "and there is one command that runs it, which is what the book prints" \
  "$([ -x "$_f/.local/bin/hub-compile-rules" ] && echo yes || echo no)" "yes"
t "a README is not installed as a program" \
  "$([ -e "$_f/.local/bin/README.md" ] && echo yes || echo no)" "no"
# The notebook step further down schedules ~/.local/bin/hub-notebook-sync and silently
# does nothing when it is missing, so THIS function is what decides whether a reader's
# notebook ever updates itself.
t "the notebook runner is installed on the machine with them" \
  "$([ -f "$_f/.local/bin/hub-notebook-sync" ] && echo yes || echo no)" "yes"
t "and the credential helper it needs is beside it" \
  "$([ -f "$_f/.local/bin/hub-notebook-env" ] && echo yes || echo no)" "yes"

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

# A JOIN names no kit (join.sh passes only KB_TOOLS_REPO, which is usually unset), so
# the kit the tools came from is written down at install time and read back when the
# argument is empty. Without this, a joined machine never got the runner, and the
# notebook step found nothing to schedule.
t "the kit the tools came from was written down beside it" \
  "$(grep -c '^HUB_TOOLS_REPO=' "$_f/.hub/device.env" 2>/dev/null)" "1"
rm -f "$_f/.local/bin/hub-notebook-sync"
( HOME="$_f" kb_install_hub_tools "$_f/hub2" "" ) >/dev/null 2>&1
t "a later run that names no kit refreshes from the one written down" \
  "$([ -f "$_f/.local/bin/hub-notebook-sync" ] && echo yes || echo no)" "yes"

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
  "$([ -f "$_c/made/profile/about-me.md" ] && [ -f "$_c/made/skills/plan-my-day.md" ] && echo yes)" "yes"
t "the starter's own AGENTS.md is used, never an invented one" \
  "$(head -1 "$_c/made/AGENTS.md" 2>/dev/null)" "# the real one"
t "a new hub is a real hub afterwards" \
  "$(kb_hub_looks_real "$_c/made" && echo yes)" "yes"

# Running it twice must not tread on a sentence they have written about themselves.
printf '# mine, edited\n' > "$_c/made/AGENTS.md"
( HOME="$_c" kb_new_hub "$_c/made" "" "$_starter" ) >/dev/null 2>&1
t "a second run keeps what they have written" \
  "$(head -1 "$_c/made/AGENTS.md")" "# mine, edited"

# The product ships its own memory page; a blank one must not replace it.
mkdir -p "$_starter/starter-hub/observations"
printf '# The page the product wrote\n' > "$_starter/starter-hub/observations/MEMORY.md"
( cd "$_starter" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m mem ) >/dev/null 2>&1
( HOME="$_c" kb_new_hub "$_c/kept" "" "$_starter" ) >/dev/null 2>&1
t "the starter's memory page survives" \
  "$(head -1 "$_c/kept/observations/MEMORY.md" 2>/dev/null)" "# The page the product wrote"

# =============================================================================
# --- WHERE A HUB MAY GO (D-179, 2026-09-02) ----------------------------------
# The default is the top of the home folder on every OS, and the folders a cloud drive
# syncs are refused with a sentence, because a synced git folder is the one thing that
# corrupts a hub. Twins of the cases in windows/test-windows.ps1. Change both.
_w="$(mktemp -d)"
mkdir -p "$_w/Documents" "$_w/Desktop" "$_w/Pictures" "$_w/Documents-old" \
         "$_w/Library/CloudStorage/OneDrive-Personal"
_r()  { HOME="$_w" OneDrive="" kb_refuse_hub_path "$1"; }
_v()  { case "$(_r "$1")" in *"synced by a cloud drive"*) echo refused ;; "") echo allowed ;; *) echo other ;; esac; }
t "the default is the top of the home folder"         "$(HOME="$_w" kb_default_hub_dir)"  "$_w/hub"
t "the home folder itself is allowed"                  "$(_v "$_w/hub")"                    "allowed"
t "a tilde means the home folder too"                  "$(_v "~/hub")"                      "allowed"
t "Documents is refused"                               "$(_v "$_w/Documents/hub")"          "refused"
t "Desktop is refused"                                 "$(_v "$_w/Desktop/hub")"            "refused"
t "Pictures is refused"                                "$(_v "$_w/Pictures/hub")"           "refused"
t "deeper inside Documents is still refused"           "$(_v "$_w/Documents/work/hub")"     "refused"
t "a Mac cloud drive folder is refused"                "$(_v "$_w/Library/CloudStorage/OneDrive-Personal/hub")" "refused"
t "a folder merely named like one is allowed"          "$(_v "$_w/Documents-old/hub")"      "allowed"
t "the refusal names the right place to go"            "$(case "$(_r "$_w/Documents/hub")" in *"$_w/hub"*) echo yes ;; esac)" "yes"
t "the root of the disk is refused on this side"       "$(case "$(_r /hub)" in *"root of the disk"*) echo refused ;; esac)" "refused"
t "a deeper system folder is an admin's business"      "$(_r /srv/hub)"                     ""
# Git Bash copies on ln -s unless MSYS=winsymlinks is set, so the case runs only where a
# real link came out of it (every Linux and every Mac).
if ln -s "$_w/Documents" "$_w/docs-link" 2>/dev/null && [ -L "$_w/docs-link" ]; then
  t "a link into Documents is judged by where it lands" "$(_v "$_w/docs-link/hub")"          "refused"
fi
t "an empty path is refused with a sentence"           "$(case "$(_r "")" in *"needs a folder path"*) echo refused ;; esac)" "refused"

# THE FOLDER RENAME, FOR SOMEBODY WHO ALREADY INSTALLED (2026-08-16)
#
# The names used to describe WHO TYPED a file: context/ what you wrote, memory/ what your
# assistant wrote. Nobody asks that question while working. The names now describe WHEN the
# file is read, which is the question that decides everything. A reader who installed before
# the change has the old names, and each case below is a way the rename could lose their work.

_m=$(mktemp -d); _mh="$_m/hub"; mkdir -p "$_mh/context" "$_mh/memory"
printf 'who I am\n' > "$_mh/context/about-me.md"
printf 'a fact\n'   > "$_mh/memory/thing.md"
kb_migrate_folder_names "$_mh" >/dev/null 2>&1
t "context/ becomes profile/, carrying the file" "$(cat "$_mh/profile/about-me.md" 2>/dev/null)" "who I am"
t "memory/ becomes observations/, carrying the file" "$(cat "$_mh/observations/thing.md" 2>/dev/null)" "a fact"
t "the old names are gone, not left as twins" \
  "$({ [ -d "$_mh/context" ] || [ -d "$_mh/memory" ]; } && echo yes || echo no)" "no"
t "rules/ is created, because it is new" "$([ -d "$_mh/rules" ] && echo yes)" "yes"

# Twice must equal once. An installer people are afraid to re-run is a broken installer.
kb_migrate_folder_names "$_mh" >/dev/null 2>&1
t "running the rename again changes nothing" "$(cat "$_mh/profile/about-me.md" 2>/dev/null)" "who I am"

# BOTH names present is the case that could silently merge two folders into one and lose
# whichever file lost the collision. It must refuse and leave both.
_m2=$(mktemp -d); _mh2="$_m2/hub"; mkdir -p "$_mh2/context" "$_mh2/profile"
printf 'old\n' > "$_mh2/context/x.md"; printf 'new\n' > "$_mh2/profile/y.md"
kb_migrate_folder_names "$_mh2" >/dev/null 2>&1
t "both folders present means both are left alone" \
  "$([ -f "$_mh2/context/x.md" ] && [ -f "$_mh2/profile/y.md" ] && echo yes)" "yes"

# A hub that never had the old names must not grow them back.
_m3=$(mktemp -d); _mh3="$_m3/hub"; mkdir -p "$_mh3/profile" "$_mh3/observations"
kb_migrate_folder_names "$_mh3" >/dev/null 2>&1
t "a hub already renamed is untouched" \
  "$({ [ -d "$_mh3/context" ] || [ -d "$_mh3/memory" ]; } && echo yes || echo no)" "no"

# A hub from before the rename is still a hub, or discovery stops finding it and the
# installer offers to build a second one beside it.
_m4=$(mktemp -d); mkdir -p "$_m4/oldhub/memory" "$_m4/oldhub/.git"
t "a pre-rename hub is still recognised as one" "$(kb_hub_looks_real "$_m4/oldhub" && echo yes)" "yes"
rm -rf "$_m" "$_m2" "$_m3" "$_m4"

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


# --- THE ASSISTANT THE PREREQS FETCH: HERMES, NOT CLAUDE CODE -----------------
# Batch AK, decided 2026-09-01: Hermes is the taught assistant from Chapter 3, so
# the reader-facing installer fetches Hermes. kb_install_claude_code stays
# defined - Chapter 5's developer door, and other products still call it - but
# kb_install_prereqs no longer touches it. The network is intercepted by
# overriding curl in a subshell, the same trick the tty cases play on
# kb_stdin_is_tty, because this suite never reaches the network.
_hm="$(mktemp -d)"
mkdir -p "$_hm/fresh" "$_hm/empty"

t "a Hermes already here is not reinstalled" \
  "$(KB_HERMES_BIN=/bin/true kb_install_hermes >/dev/null 2>&1; echo $?)" "0"
t "and it is reported as already here, not fetched" \
  "$(KB_HERMES_BIN=/bin/true kb_install_hermes 2>&1 | grep -c 'already here')" "1"

# The install path, end to end, with the network stood in for by a local script.
# The official installer's one observable promise is a hermes command that works
# afterwards, so that is what the fake delivers and what the case asserts.
cat > "$_hm/fake-installer.sh" <<'FAKE'
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/hermes"
chmod +x "$HOME/.local/bin/hermes"
FAKE
out="$( ( curl() { cat "$_hm/fake-installer.sh"; }
          HOME="$_hm/fresh"; PATH="/usr/bin:/bin"
          kb_install_hermes; echo "rc=$?" ) 2>&1 )"
case "$out" in *"rc=0"*) t "an absent Hermes is fetched and becomes usable" yes yes ;;
               *) t "an absent Hermes is fetched and becomes usable" "$out" "rc=0" ;; esac
t "and the launcher landed where Hermes puts it" \
  "$([ -x "$_hm/fresh/.local/bin/hermes" ] && echo yes)" "yes"

# A fetch that delivers nothing must warn and note the miss, never claim success.
out="$( ( curl() { :; }
          HOME="$_hm/empty"; PATH="/usr/bin:/bin"
          KB_MISSING=""; kb_install_hermes >/dev/null 2>&1; echo "rc=$? missing=$KB_MISSING" ) )"
case "$out" in *"rc=1"*Hermes*) t "a failed fetch warns and notes the miss" yes yes ;;
               *) t "a failed fetch warns and notes the miss" "$out" "rc=1 ... Hermes" ;; esac

# The composition: which assistant the prereqs ask for. The tool half is stubbed
# so this never reaches a package manager, per this file's own first promise.
out="$( ( kb_install_one() { ok "$4 is already here"; }
          KB_HERMES_BIN=/bin/true; kb_install_prereqs ) 2>&1 )"
case "$out" in *Hermes*) t "the prereqs fetch Hermes" yes yes ;;
               *) t "the prereqs fetch Hermes" "$out" "mentions Hermes" ;; esac
t "and no longer fetch Claude Code" "$(printf '%s' "$out" | grep -c 'Claude Code')" "0"

# The detector, repaired. config.yaml is the marker every install has, where the
# old profiles/ subfolder missed any install still on its default profile - which
# is how Hermes was invisible on the machine of the person writing the book about
# it. HERMES_HOME wins, because that is where a relocated install actually lives.
mkdir -p "$_hm/hh" "$_hm/native/.hermes" "$_hm/bare"
: > "$_hm/hh/config.yaml"
: > "$_hm/native/.hermes/config.yaml"
t "hermes is seen where HERMES_HOME points" \
  "$( (HOME="$_hm/bare" HERMES_HOME="$_hm/hh" KB_ASSUME_TOOLS= kb_ai_tool_detected hermes && echo yes) )" "yes"
t "a default-profile install with no profiles folder is still seen" \
  "$( (HOME="$_hm/native" HERMES_HOME= KB_ASSUME_TOOLS= kb_ai_tool_detected hermes && echo yes) )" "yes"
t "no config file anywhere means not seen" \
  "$( (HOME="$_hm/bare" HERMES_HOME= KB_ASSUME_TOOLS= kb_ai_tool_detected hermes || echo no) )" "no"
t "the report calls it Hermes, not chat bots" \
  "$(kb_ai_tool_info hermes)" "prompts|Hermes|"
rm -rf "$_hm"


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

# The file that tells CLAUDE CODE where the notebook is. Not "the assistant": Hermes
# never reads a folder .mcp.json, checked in its source, so a kit that says otherwise is
# telling a reader their hub carries configuration it does not carry.
_mcpout="$(kb_write_mcp_config "$_n/hub" 2>&1)"
t "Claude Code is given an .mcp.json" "$([ -f "$_n/hub/.mcp.json" ] && echo yes || echo no)" "yes"
t "the file says plainly that Hermes does not read it" \
  "$(grep -c "Hermes does not read it" "$_n/hub/.mcp.json")" "1"
t "and it names the commands that DO tell Hermes" \
  "$(grep -c "hermes mcp add" "$_n/hub/.mcp.json")" "1"
t "nothing in it claims to configure \"your assistant\" in general" \
  "$(grep -c "tells your assistant" "$_n/hub/.mcp.json")" "0"
t "the installer says which tool it wrote the file for" \
  "$(printf '%s' "$_mcpout" | grep -c "for Claude Code")" "1"
t "and repeats that Hermes needs telling separately" \
  "$(printf '%s' "$_mcpout" | grep -c "Hermes does not read that file")" "1"
t "the connection NAMES the credential rather than carrying one" \
  "$(grep -c 'Bearer \${MENERIO_API_KEY}' "$_n/hub/.mcp.json")" "1"
# python3, then python. Git Bash on Windows ships the launcher as `python` only, and this
# suite is run there because that is where the .exe installer is built. A test that fails for
# want of an interpreter reads exactly like a broken installer, and it hid nothing useful.
_py=""
for _c in python3 python; do "$_c" -c '' >/dev/null 2>&1 && { _py="$_c"; break; }; done
if [ -n "$_py" ]; then
  t "and it is valid JSON, which is the only way an assistant will read it" \
    "$("$_py" -c 'import json,sys;json.load(open(sys.argv[1]));print("ok")' "$_n/hub/.mcp.json" 2>/dev/null)" "ok"
else
  echo "  skip  valid JSON: no python on this machine to read it with"
fi
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

# Every front door offers the notebook, not only the create path. Until 2026-08-18
# only setup-hub.sh called the connect step: a joined second machine got the runner
# installed and the credentials sitting in the folder, and nothing introduced them.
t "join.sh offers the notebook connection" \
  "$(grep -c '^kb_connect_notebook "\$HUB"' join.sh)" "1"
t "the Windows join offers it too" \
  "$(grep -c '^Connect-KitNotebook -Hub \$Hub' join.ps1)" "1"

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
    "$(age -d -i "$_n/home/.hub/age-key.txt" "$_n/hub/secrets/hub-secrets.env.age" | sed -n 's/^MENERIO_API_KEY=//p')" \
    "test-token-not-a-real-one-0123456789"
  t "one paste leaves exactly one credential, because one key does both jobs" \
    "$(age -d -i "$_n/home/.hub/age-key.txt" "$_n/hub/secrets/hub-secrets.env.age" | grep -c '^MENERIO_')" "1"
  ( kb_store_notebook_token "$_n/hub" "second-token-still-not-real-98765" ) >/dev/null 2>&1
  t "connecting again replaces the credential instead of keeping two" \
    "$(age -d -i "$_n/home/.hub/age-key.txt" "$_n/hub/secrets/hub-secrets.env.age" | grep -c '^MENERIO_API_KEY=')" "1"
  # THE CASE THAT ALMOST DESTROYED A REAL HUB. A folder carrying credentials this
  # computer cannot open must be REFUSED, never rewritten: re-locking it to this
  # machine's key shuts every other computer out of every credential at once, silently.
  # This is what happened on 2026-08-16, to a live hub, during a test run.
  _other=$(mktemp -d)
  age-keygen -o "$_other/key" 2>/dev/null
  printf 'MENERIO_API_KEY=belongs-to-someone-else-0123456789
'     | age -r "$(age-keygen -y "$_other/key")" -o "$_n/hub/secrets/hub-secrets.env.age"
  _before="$(sha256sum "$_n/hub/secrets/hub-secrets.env.age" | cut -d' ' -f1)"
  t "a folder this computer cannot open reports 'locked-out', never 'none'"     "$(kb_notebook_state "$_n/hub")" "locked-out"
  t "and pasting a token into it is refused"     "$(kb_store_notebook_token "$_n/hub" "a-new-token-0123456789" >/dev/null 2>&1; echo $?)" "1"
  t "the other computers' credentials are byte-for-byte untouched"     "$(sha256sum "$_n/hub/secrets/hub-secrets.env.age" | cut -d' ' -f1)" "$_before"
  t "and the whole connect step changes nothing there either"     "$(kb_connect_notebook "$_n/hub" >/dev/null 2>&1; sha256sum "$_n/hub/secrets/hub-secrets.env.age" | cut -d' ' -f1)" "$_before"
  rm -rf "$_other" "$_n/hub/secrets/hub-secrets.env.age"
  ( kb_store_notebook_token "$_n/hub" "test-token-not-a-real-one-0123456789" ) >/dev/null 2>&1

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

# ---------------------------------------------------------------------------
# WHEN A KEY RUNS OUT: the record beside the keys.
#
# A key is a thing with a lifespan, and the day it dies nothing announces it.
# This file is the only place a date is written down, so the morning brief and
# hub-check-keys can both read it. It must never hold a key, must never
# overwrite what the reader wrote in it, and must arrive on BOTH roads: a hub
# made fresh by the installer, and a hub that gains keys later.
# ---------------------------------------------------------------------------
echo
echo "== when a key runs out (secrets/expires.txt)"
_x="$(mktemp -d)"
mkdir -p "$_x/hub"

kb_seed_expiry_record "$_x/hub" >/dev/null 2>&1
t "a hub with no record gets one" \
  "$([ -f "$_x/hub/secrets/expires.txt" ] && echo yes || echo no)" "yes"
t "and it explains its own three columns, so nobody has to be told twice" \
  "$(grep -c 'the page you get a new one from' "$_x/hub/secrets/expires.txt")" "1"
t "and it warns against the one thing that would ruin it" \
  "$(grep -c 'NEVER PUT A KEY ITSELF IN HERE' "$_x/hub/secrets/expires.txt")" "1"
t "it holds no key of its own: every line in it is a comment" \
  "$(grep -vc '^[[:space:]]*\(#.*\)\?$' "$_x/hub/secrets/expires.txt")" "0"

printf 'MY_KEY  2027-01-01  https://example.com  # mine\n' >> "$_x/hub/secrets/expires.txt"
kb_seed_expiry_record "$_x/hub" >/dev/null 2>&1
t "running the installer again never touches what the reader wrote in it" \
  "$(grep -c '^MY_KEY' "$_x/hub/secrets/expires.txt")" "1"
t "and it is silent the second time, because there was nothing to do" \
  "$(kb_seed_expiry_record "$_x/hub" 2>&1)" ""

# The other road: a hub that had no record and then gains keys. Before this, the
# record only ever reached a hub made after the day it was written, so every
# reader who already had one carried keys with no dates and nothing said so.
rm -rf "$_x/hub2"; mkdir -p "$_x/hub2"
kb_new_hub "$_x/hub2" >/dev/null 2>&1 || true
t "a brand new hub carries the record from day one, not after an upgrade" \
  "$([ -f "$_x/hub2/secrets/expires.txt" ] && echo yes || echo no)" "yes"

# The two roads must lay down the SAME file. The reader kit ships its own copy
# inside starter-hub/, so a fresh hub gets it by copy and an older one gets it
# from the function above. Two copies of one file is two places to fix a typo,
# and the one nobody edits is the one every reader ends up with.
_starter="$(cd "$(dirname "$0")/../teach-it-once-kit" 2>/dev/null && pwd)"
if [ -n "$_starter" ] && [ -f "$_starter/starter-hub/secrets/expires.txt" ]; then
  t "the copy in the reader kit's starter folder is the same file, to the byte" \
    "$(cmp -s "$_starter/starter-hub/secrets/expires.txt" "$_x/hub2/secrets/expires.txt" 2>/dev/null && echo same || echo different)" "same"
else
  echo "  skip  the starter folder's copy is not on this computer to compare with"
fi
rm -rf "$_x"


# ---------------------------------------------------------------------------
# WHAT RUNS OUT, AND WHEN (due/). A calendar reminder fires on a date and knows nothing
# else, so it goes off about something already done and a person stops reading reminders.
# This room is the other shape, and the installer has to deliver it to BOTH kinds of hub:
# a brand new one and one somebody has had for months.
# ---------------------------------------------------------------------------
echo
echo "== the things with a last day (due/)"
_x="$(mktemp -d)"
mkdir -p "$_x/hub"

kb_seed_due_folder "$_x/hub" >/dev/null 2>&1
t "a hub with no due room gets one" \
  "$([ -f "$_x/hub/due/README.md" ] && echo yes || echo no)" "yes"
t "and it teaches the window rather than a due date" \
  "$(grep -c 'the first day you can do the thing, and the last day you' "$_x/hub/due/README.md")" "1"
t "and it says a reader needs no calendar for any of it" \
  "$(grep -c 'You do not need a calendar' "$_x/hub/due/README.md")" "1"
t "and it carries the refusal that keeps this from becoming a to-do list" \
  "$(grep -c 'No date, not eligible' "$_x/hub/due/README.md")" "1"
t "and it says the fourth question is the one that matters" \
  "$(grep -c 'How could your hub tell you did it, without asking you' "$_x/hub/due/README.md")" "1"

printf 'mine\n' > "$_x/hub/due/car-service.md"
kb_seed_due_folder "$_x/hub" >/dev/null 2>&1
t "running the installer again never touches a deadline the reader wrote" \
  "$(cat "$_x/hub/due/car-service.md")" "mine"
t "and it is silent the second time, because there was nothing to do" \
  "$(kb_seed_due_folder "$_x/hub" 2>&1)" ""

# The other road: a hub made from nothing today. Before the expiry record learned this
# lesson, a new room only ever reached hubs made after the day it was written.
rm -rf "$_x/hub3"; mkdir -p "$_x/hub3"
kb_new_hub "$_x/hub3" >/dev/null 2>&1 || true
t "a brand new hub carries the due room from day one, not after an upgrade" \
  "$([ -f "$_x/hub3/due/README.md" ] && echo yes || echo no)" "yes"

# The two roads must lay down the SAME file, for the same reason the expiry record must.
_starter="$(cd "$(dirname "$0")/../teach-it-once-kit" 2>/dev/null && pwd)"
if [ -n "$_starter" ] && [ -f "$_starter/starter-hub/due/README.md" ]; then
  t "the copy in the reader kit's starter folder is the same file, to the byte" \
    "$(cmp -s "$_starter/starter-hub/due/README.md" "$_x/hub3/due/README.md" 2>/dev/null && echo same || echo different)" "same"
  t "and the card the book sends the reader to is in the kit" \
    "$([ -f "$_starter/procedures/what-runs-out-and-when.md" ] && echo yes || echo no)" "yes"
  t "and the card says in its own words that no Google account is needed" \
    "$(grep -c 'You do not need a Google account' "$_starter/procedures/what-runs-out-and-when.md")" "1"
  t "and the program the card tells the reader to type is in the kit" \
    "$([ -f "$_starter/tools/due.js" ] && echo yes || echo no)" "yes"
else
  echo "  skip  the reader kit is not on this computer to compare with"
fi
rm -rf "$_x"

# ---------------------------------------------------------------------------
# THE LAUNCHERS. Every command the book tells a reader to TYPE needs one. Before
# 2026-08-29 only the prompt collector got one on either platform, so hub-check-keys and
# hub-compile-rules were shell scripts with no launcher, and the book printed both.
# ---------------------------------------------------------------------------
echo
echo "== a launcher for every command the book prints"
_l="$(mktemp -d)"
mkdir -p "$_l/kit/tools" "$_l/hub"
for f in prompt-harvest.js compile-rules.js check-keys.js due.js; do printf '// %s\n' "$f" > "$_l/kit/tools/$f"; done
git -C "$_l/kit" init -q 2>/dev/null
git -C "$_l/kit" add -A >/dev/null 2>&1
git -C "$_l/kit" -c user.email=t@t -c user.name=t commit -q -m tools >/dev/null 2>&1
HOME="$_l/home" kb_install_hub_tools "$_l/hub" "$_l/kit" >/dev/null 2>&1
for cmd in hub-prompt-harvest hub-compile-rules hub-check-keys hub-due; do
  t "$cmd got a launcher" "$([ -f "$_l/home/.local/bin/$cmd" ] && echo yes || echo no)" "yes"
done
t "and a launcher runs the program next to it, not a path baked in at install time" \
  "$(grep -c 'dirname "\$0"' "$_l/home/.local/bin/hub-due")" "1"
# A kit that ships none of them must get none of them, silently: every other product
# using this library ships no tools folder at all.
rm -f "$_l/kit/tools/due.js"
git -C "$_l/kit" add -A >/dev/null 2>&1
git -C "$_l/kit" -c user.email=t@t -c user.name=t commit -q -m drop >/dev/null 2>&1
rm -rf "$_l/home"
HOME="$_l/home" kb_install_hub_tools "$_l/hub" "$_l/kit" >/dev/null 2>&1
t "a kit that ships no due.js gets no hub-due, and says nothing about it" \
  "$([ -f "$_l/home/.local/bin/hub-due" ] && echo yes || echo no)" "no"
rm -rf "$_l"

rm -rf "$_f"


echo
echo "== one skills room, and the installer proves it wired something"
#
# THE BUG THESE EXIST FOR. Until 2026-09-01 the installer linked .agents/skills to
# .claude/skills whenever .claude/skills existed. On a hub whose recipes live in
# the visible skills/ room, the top-up had just created .claude/skills EMPTY, so
# every non-Claude assistant was pointed at an empty folder while six recipes sat
# unreachable, under a green tick. Measured on a real hub, not imagined.
#
# Every case below drives Hermes through a STUB. That is not tidiness: an early
# run of kb_wire_skills from a scratch folder wrote a temp path into the author's
# own live config, because the function found the real hermes on PATH.
_sk=$(mktemp -d); mkdir -p "$_sk/bin"
printf '#!/bin/sh\necho "$*" >> "%s/calls.log"\nif [ "$2" = "get" ]; then printf -- "- /existing/team-skills\\n"; fi\nexit 0\n' "$_sk" > "$_sk/bin/hermes"
chmod +x "$_sk/bin/hermes"
export KB_HERMES_BIN="$_sk/bin/hermes"

t "an empty folder holds no recipes"        "$(kb_count_recipes "$_sk/nope")"  "0"
mkdir -p "$_sk/flat"; : > "$_sk/flat/a.md"; : > "$_sk/flat/b.md"
t "flat .md recipes are counted"            "$(kb_count_recipes "$_sk/flat")"  "2"
mkdir -p "$_sk/nested/deep"; : > "$_sk/nested/deep/SKILL.md"
t "a folder recipe with a SKILL.md counts"  "$(kb_count_recipes "$_sk/nested")" "1"

# Which room is the real one. Detected, never assumed.
_r1=$(mktemp -d); mkdir -p "$_r1/skills" "$_r1/.claude/skills"; : > "$_r1/skills/a.md"
t "the visible room wins when it holds the recipes" "$(kb_skills_room "$_r1")" "$_r1/skills"
_r2=$(mktemp -d); mkdir -p "$_r2/.claude/skills"; : > "$_r2/.claude/skills/a.md"
t "a Claude-era hub keeps its recipes where they are" "$(kb_skills_room "$_r2")" "$_r2/.claude/skills"
_r3=$(mktemp -d)
t "a brand new hub is given the visible room" "$(kb_skills_room "$_r3")" "$_r3/skills"

# THE UNQUOTING, WITH EXACT BYTES. Every rule the kit ships starts with `*`, which YAML
# reads as an ALIAS, so Hermes hands them all back QUOTED. Reading them raw is how a
# second install run added all eighteen again with the quotes baked in, and the list
# reached seventy-two entries after three runs on the real box.
#
# These use a $q built with printf rather than a literal, because the bug this replaces
# was ENTIRELY about quoting: ${v#'} does not strip a quote, the shell reads it as
# opening a quoted section and the strip silently does nothing. A test written with
# careless quotes would have agreed with the broken version.
_q=$(printf '\047')
t "a quoted rule comes back as the rule" \
  "$(kb_yaml_unquote "${_q}*shred *${_q}")" "*shred *"
t "an unquoted one is left alone"        \
  "$(kb_yaml_unquote "*shred *")" "*shred *"
t "a value already corrupted by the old bug is recovered" \
  "$(kb_yaml_unquote "${_q}${_q}${_q}*shred *${_q}${_q}${_q}")" "*shred *"
t "a rule with no star in it is handled the same way" \
  "$(kb_yaml_unquote "${_q}ufw --force reset${_q}")" "ufw --force reset"
t "an empty value stays empty"           "$(kb_yaml_unquote "")" ""
t "and a lone quote is not eaten"        "$(kb_yaml_unquote "$_q")" "$_q"

# The merge. `hermes config set` REPLACES a list, so this is how a reader loses a
# team folder they added themselves.
: > "$_sk/calls.log"
_m=$(mktemp -d); mkdir -p "$_m/skills"; : > "$_m/skills/a.md"
kb_wire_skills "$_m" >/dev/null 2>&1
t "an entry already in external_dirs survives" \
  "$(grep -c '"/existing/team-skills"' "$_sk/calls.log")" "1"
t "and the hub's room is added, not substituted" \
  "$(grep -c "\"$_m/skills\"\]" "$_sk/calls.log")" "1"

# Never write when nothing needs writing.
printf '#!/bin/sh\necho "$*" >> "%s/calls2.log"\nif [ "$2" = "get" ]; then printf -- "- %s\\n"; fi\nexit 0\n' "$_sk" "$_m/skills" > "$_sk/bin/hermes"
chmod +x "$_sk/bin/hermes"; : > "$_sk/calls2.log"
kb_wire_skills "$_m" >/dev/null 2>&1
t "a room Hermes already reads is not written again" \
  "$(grep -c 'config set' "$_sk/calls2.log")" "0"

# THE VERSION THAT STORES A LIST AS TEXT. Hermes 0.20.0 does not parse a JSON
# list on `config set`: it stores the whole text as one string, which its own
# readers then ignore, so the setting lands and does nothing. Measured on the
# book's own rehearsal server. The stub stores verbatim and echoes the store
# back RAW, exactly as that version does, and the kit must say the truth out
# loud rather than print a success line over an inert setting.
printf '#!/bin/sh\nif [ "$2" = "get" ]; then if [ -s "%s/extstore" ]; then cat "%s/extstore"; echo; fi; fi\nif [ "$2" = "set" ]; then printf -- %%s "$4" > "%s/extstore"; fi\nexit 0\n' "$_sk" "$_sk" "$_sk" > "$_sk/bin/hermes"
chmod +x "$_sk/bin/hermes"
printf '%s' '["/existing/team-skills"]' > "$_sk/extstore"
t "a raw string read back is no list entry at all" \
  "$(kb_hermes_list skills.external_dirs | grep -c .)" "0"
out="$(kb_hermes_skills_dir "$_m/skills" 2>&1)"
t "a Hermes that stores the room as text is told on, not celebrated" \
  "$(printf '%s' "$out" | grep -c 'text it does not read')" "1"

# THE READ-BACK THAT CRIED WOLF. The server installer (2026-09-02, Hermes 0.21.0) wrote
# all eighteen deny rules, Hermes stored them as a real list, `approvals test` refused
# the firewall reset with exit 3, and the kit still printed "The leash is NOT on".
# The check was `kb_hermes_list approvals.deny | grep -q RULE` inside a script running
# `set -o pipefail`. grep -q exits on the FIRST match (the rule is 11th of 18), the
# producer's next printf hits a closed pipe, dies with 141, and pipefail hands that 141
# to the `if`. A race, so it passed every earlier run and failed on the one that was
# being transcribed for the book. Capture the list first, then look inside it.
cat > "$_sk/bin/hermes" <<'STUB'
#!/bin/sh
if [ "$2" = "get" ]; then i=0; while [ $i -lt 400 ]; do i=$((i+1)); printf -- "- entry-%s
" "$i"; done; fi
exit 0
STUB
chmod +x "$_sk/bin/hermes"
t "a list entry is found even when pipefail is on and it is the FIRST of many"   "$( ( set -o pipefail; kb_hermes_list_has some.key entry-1 ) >/dev/null 2>&1; echo $? )" "0"
t "and an entry that is not there is not invented"   "$( ( set -o pipefail; kb_hermes_list_has some.key entry-401 ) >/dev/null 2>&1; echo $? )" "1"

printf '#!/bin/sh\necho "$*" >> "%s/calls.log"\nif [ "$2" = "get" ]; then printf -- "- /existing/team-skills\\n"; fi\nexit 0\n' "$_sk" > "$_sk/bin/hermes"
chmod +x "$_sk/bin/hermes"

# Git Bash on Windows turns `ln -s` into a COPY, which would pass a naive check
# while sharing nothing, so the link cases run for real on Linux only. This block
# probes for itself rather than reusing the one further up, which is torn down
# long before here: borrowing it made every case below skip silently on Linux,
# which is the one platform they exist to cover.
_skprobe=$(mktemp -d); mkdir "$_skprobe/real"; ln -sfn "$_skprobe/real" "$_skprobe/link" 2>/dev/null
if [ -L "$_skprobe/link" ]; then
  # The exact shipped defect: recipes visible, .claude/skills empty.
  _d1=$(mktemp -d); mkdir -p "$_d1/skills" "$_d1/.claude/skills"
  for _n in a b c d e f; do : > "$_d1/skills/$_n.md"; done
  : > "$_d1/.claude/skills/.gitkeep"
  kb_wire_skills "$_d1" >/dev/null 2>&1
  t "the empty placeholder becomes a link, not a second room" \
    "$([ -L "$_d1/.claude/skills" ] && echo yes)" "yes"
  t "and it resolves to the room the reader can see" \
    "$(cd "$_d1/.claude/skills" && pwd -P)" "$(cd "$_d1/skills" && pwd -P)"
  t "so Claude Code reaches all six recipes, which was the bug" \
    "$(kb_count_recipes "$_d1/.claude/skills")" "6"
  t "and so does everything that is not Claude Code" \
    "$(kb_count_recipes "$_d1/.agents/skills")" "6"
  t "exactly one real skills folder exists in the hub" \
    "$(find "$_d1" -name skills -type d | grep -c .)" "1"

  # GIT AND THE DOORS (2026-09-02). On Windows a junction looks like a folder to git,
  # so a reader who commits their hub commits the recipes twice; a Linux clone then
  # holds two real rooms. The doors are ignored and untracked; the real room stays.
  _g1=$(mktemp -d); git -C "$_g1" init -q -b main 2>/dev/null || git -C "$_g1" init -q
  mkdir -p "$_g1/skills/one" "$_g1/.claude/skills/one"; : > "$_g1/skills/one/SKILL.md"; : > "$_g1/.claude/skills/one/SKILL.md"
  printf 'node_modules/
' > "$_g1/.gitignore"
  git -C "$_g1" add -A >/dev/null 2>&1; git -C "$_g1" -c user.name=t -c user.email=t@t commit -qm "before" >/dev/null 2>&1
  kb_wire_skills "$_g1" >/dev/null 2>&1
  t "a hidden door that is a link is listed in .gitignore" "$(grep -cxF '.claude/skills' "$_g1/.gitignore")" "1"
  t "and so is the other door" "$(grep -cxF '.agents/skills' "$_g1/.gitignore")" "1"
  t "and git no longer tracks the door's copy of the recipes" "$(git -C "$_g1" ls-files .claude/skills | grep -c .)" "0"
  t "while the real room stays tracked" "$(git -C "$_g1" ls-files skills | grep -c .)" "1"
  t "and the reader's own ignore line survives" "$(grep -cxF 'node_modules/' "$_g1/.gitignore")" "1"
  # A Claude-era git hub: the real room is .claude/skills and must stay tracked.
  _g2=$(mktemp -d); git -C "$_g2" init -q -b main 2>/dev/null || git -C "$_g2" init -q
  mkdir -p "$_g2/.claude/skills/one"; : > "$_g2/.claude/skills/one/SKILL.md"
  git -C "$_g2" add -A >/dev/null 2>&1; git -C "$_g2" -c user.name=t -c user.email=t@t commit -qm "before" >/dev/null 2>&1
  kb_wire_skills "$_g2" >/dev/null 2>&1
  t "a Claude-era hub keeps its real room tracked" "$(git -C "$_g2" ls-files .claude/skills | grep -c .)" "1"
  t "and does not ignore it" "$(grep -cxF '.claude/skills' "$_g2/.gitignore" 2>/dev/null || echo 0)" "0"
  t "but its .agents/skills door is ignored" "$(grep -cxF '.agents/skills' "$_g2/.gitignore")" "1"

  # A hub whose recipes really do live in .claude/skills must not be fed to
  # itself. Getting this wrong copies a folder into itself and moves it aside.
  _d2=$(mktemp -d); mkdir -p "$_d2/.claude/skills"
  for _n in x y z; do : > "$_d2/.claude/skills/$_n.md"; done
  kb_wire_skills "$_d2" >/dev/null 2>&1
  t "a Claude-era hub keeps its three recipes" "$(kb_count_recipes "$_d2/.claude/skills")" "3"
  t "and nothing was moved aside behind its back" \
    "$(find "$_d2" -name '*.replaced-*' | grep -c .)" "0"

  # The old backwards link, already on disk, must be repaired rather than trusted.
  _d3=$(mktemp -d); mkdir -p "$_d3/skills" "$_d3/.claude/skills" "$_d3/.agents"
  for _n in a b c d e f; do : > "$_d3/skills/$_n.md"; done
  ln -sfn "$_d3/.claude/skills" "$_d3/.agents/skills"
  t "before: the old link reached nothing" "$(kb_count_recipes "$_d3/.agents/skills")" "0"
  kb_wire_skills "$_d3" >/dev/null 2>&1
  t "after: the same link reaches every recipe" "$(kb_count_recipes "$_d3/.agents/skills")" "6"

  # Twice equals once, or re-running the installer is a thing people fear.
  _d4=$(mktemp -d); mkdir -p "$_d4/skills"; : > "$_d4/skills/a.md"
  kb_wire_skills "$_d4" >/dev/null 2>&1
  find "$_d4" | sort > "$_sk/before.txt"
  kb_wire_skills "$_d4" >/dev/null 2>&1
  find "$_d4" | sort > "$_sk/after.txt"
  t "a second run changes nothing on disk" \
    "$(cmp -s "$_sk/before.txt" "$_sk/after.txt" && echo same || echo different)" "same"

  # A real folder with real work standing where the link belongs is never deleted.
  _d5=$(mktemp -d); mkdir -p "$_d5/skills" "$_d5/.claude/skills"
  : > "$_d5/skills/mine.md"; : > "$_d5/.claude/skills/theirs.md"
  kb_wire_skills "$_d5" >/dev/null 2>&1
  t "a recipe found in the hidden folder is carried into the visible room" \
    "$([ -f "$_d5/skills/theirs.md" ] && echo yes)" "yes"
  t "and the folder it came from is kept, not deleted" \
    "$(find "$_d5" -name '*.replaced-*' | grep -c .)" "1"
else
  echo "  skip  the link cases need real symlinks (Git Bash copies instead)"
fi
rm -rf "$_skprobe"
unset KB_HERMES_BIN
rm -rf "$_sk"

echo
echo "== where Hermes works, and proving it rather than reading the setting back"
#
# WHAT THESE GUARD. The kit shipped `hermes config set workspace "$HUB"`, which is not
# a recognised key: Hermes warned, the warning went to /dev/null, and the reader was
# told the workspace was set. Four of the six known ways to point Hermes at a folder
# are silent no-ops like that one, so v2 sets terminal.cwd and then PROVES the folder
# is readable by having Hermes read a file in it.
#
# The stub below is a faithful little Hermes rather than a yes-man. `-z` reads the
# marker file RELATIVE to whatever terminal.cwd says, which is exactly the behaviour
# measured on hardware, so STUB_MODE=ignore reproduces the half-connected failure and
# the check can be proved to catch it. A stub that always said yes would test nothing.
_hb=$(mktemp -d); mkdir -p "$_hb/bin"
cat > "$_hb/bin/hermes" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
if [ "$1" = "auth" ] && [ "$2" = "list" ]; then
  [ "${STUB_NO_CREDENTIAL:-0}" = "1" ] || echo "openai-codex (1 credentials):"
fi
if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "terminal.cwd" ]; then
  if [ -s "$STUB_CWDFILE" ]; then cat "$STUB_CWDFILE"; else echo "."; fi
fi
if [ "$1" = "config" ] && [ "$2" = "set" ] && [ "$3" = "terminal.cwd" ]; then
  printf '%s' "$4" > "$STUB_CWDFILE"
fi
if [ "$1" = "-z" ]; then
  case "${STUB_MODE:-honour}" in
    parrot) echo "$2"; exit 0 ;;
    # A one-shot that reached no model at all, and still exits 0. Measured on hardware.
    http400) echo 'HTTP 400: {"detail":"The model is not supported when using Codex with a ChatGPT account."}'; exit 0 ;;
    ratelimit) echo 'API call failed after 3 retries: HTTP 429: Rate limit reached for this account.'; exit 0 ;;
    noprovider) echo "hermes -z: agent failed: No inference provider configured. Run 'hermes model' to choose a provider and model, or set an API key."; exit 0 ;;
    ignore) d="$STUB_ELSEWHERE" ;;
    *)      if [ -s "$STUB_CWDFILE" ]; then d=$(cat "$STUB_CWDFILE"); else d="."; fi ;;
  esac
  f=$(printf '%s' "$2" | sed -n 's/.*Read the file \([^ ]*\) in.*/\1/p')
  cat "$d/$f" 2>/dev/null || echo "File not found: $f"
fi
exit 0
STUB
chmod +x "$_hb/bin/hermes"
export KB_HERMES_BIN="$_hb/bin/hermes"
export STUB_LOG="$_hb/calls.log" STUB_CWDFILE="$_hb/terminal-cwd"
export STUB_ELSEWHERE="$_hb/elsewhere"
mkdir -p "$STUB_ELSEWHERE"; : > "$STUB_LOG"

_hh=$(mktemp -d)/hub; mkdir -p "$_hh"; _hhr=$(cd "$_hh" && pwd -P)
kb_point_hermes_at_hub "$_hh" >/dev/null 2>&1; _rc=$?

t "terminal.cwd is set to the hub's absolute path" "$(cat "$STUB_CWDFILE")" "$_hhr"
t "and the whole thing succeeds when the folder is readable" "$_rc" "0"
t "workspace is never set, because it is not a key" \
  "$(grep -c 'config set workspace' "$STUB_LOG")" "0"
t "the proof asks for the file by a RELATIVE name, or it proves nothing" \
  "$(grep -c 'Read the file \.hub-reachable-check in' "$STUB_LOG")" "1"
t "the marker file is not left behind in the reader's hub" \
  "$(find "$_hhr" -name '.hub-reachable-check' | grep -c .)" "0"

# Twice equals once: a hub already pointed at is not written again.
: > "$STUB_LOG"
kb_point_hermes_at_hub "$_hh" >/dev/null 2>&1
t "a second run does not set terminal.cwd again" \
  "$(grep -c 'config set terminal.cwd' "$STUB_LOG")" "0"

# THE CASE THAT MATTERS MOST. The setting reads back perfectly and the agent still
# cannot open the folder. Before this check that shipped as a green tick.
: > "$STUB_LOG"
STUB_MODE=ignore
export STUB_MODE
_hi=$(mktemp -d)/hub; mkdir -p "$_hi"
out="$(kb_point_hermes_at_hub "$_hi" 2>&1)"; _rc=$?
t "an agent that ignores terminal.cwd is caught, not congratulated" "$_rc" "1"
t "and it is named as the half-connected shape rather than as a mystery" \
  "$(printf '%s' "$out" | grep -c 'could not read a file')" "1"
# The warning quotes the answer, because "half connected" and "the model ignored the
# ask" look identical from the outside and only the reply itself tells them apart.
# A real Windows e2e burned a round trip on exactly this.
t "and the reader is shown what Hermes answered, not left to guess" \
  "$(printf '%s' "$out" | grep -c 'File not found: .hub-reachable-check')" "1"

# A PROVIDER FAILURE IS NOT A FOLDER FAILURE, and telling a reader their hub is half
# connected because their model is misconfigured is the workspace lie pointed the other
# way. Found by running the installer on hardware: the test account default was a model
# its own subscription cannot serve, so every one-shot came back HTTP 400 and the
# installer blamed terminal.cwd.
: > "$STUB_LOG"
STUB_MODE=http400; export STUB_MODE
_hu=$(mktemp -d)/hub; mkdir -p "$_hu"
t "a one-shot that reached no model is unreachable, not a failed read"   "$(kb_hermes_reads_hub "$_hu")" "unreachable"
out="$(kb_point_hermes_at_hub "$_hu" 2>&1)"; _rc=$?
t "and that is not reported as a broken hub" "$_rc" "0"
t "the reader is told it is a provider problem"   "$(printf '%s' "$out" | grep -c 'provider problem and not a folder problem')" "1"
t "and is shown what Hermes actually said"   "$(printf '%s' "$out" | grep -c 'HTTP 400')" "1"
t "the half-connected warning is NOT printed for a provider error"   "$(printf '%s' "$out" | grep -c 'could not read a file')" "0"
STUB_MODE=ratelimit
t "a rate limit is the same story" "$(kb_hermes_reads_hub "$_hu")" "unreachable"
# Hermes 0.20.0's wording for the same condition. A credential can be present
# (a gh CLI token is auto-detected as one) while no model is configured, so the
# credential gate passes and only this net catches it. Measured on the book's
# own rehearsal server, where the miss called a correctly wired hub broken.
STUB_MODE=noprovider
t "a missing inference provider is unreachable, not a broken folder" \
  "$(kb_hermes_reads_hub "$_hu")" "unreachable"
unset STUB_MODE

# A parrot passes nothing. The token lives only in the file, never in the prompt, so an
# agent that echoes the prompt straight back cannot fake a read.
STUB_MODE=parrot
_hp=$(mktemp -d)/hub; mkdir -p "$_hp"
t "an agent that only echoes the prompt back does not count as reading the file" \
  "$(kb_hermes_reads_hub "$_hp")" "no"
unset STUB_MODE

# A first install, before the reader has signed in anywhere. Crying wolf here is how an
# installer teaches people to ignore it.
: > "$STUB_LOG"
STUB_NO_CREDENTIAL=1
export STUB_NO_CREDENTIAL
_hn=$(mktemp -d)/hub; mkdir -p "$_hn"
out="$(kb_point_hermes_at_hub "$_hn" 2>&1)"; _rc=$?
t "no provider yet is not a failure" "$_rc" "0"
t "the setting still lands with no provider" \
  "$(grep -c 'config set terminal.cwd' "$STUB_LOG")" "1"
t "and no one-shot is attempted with nothing to call" "$(grep -c -- '-z' "$STUB_LOG")" "0"
t "a folder cannot be proved readable with no credential" \
  "$(kb_hermes_reads_hub "$_hn")" "unavailable"
unset STUB_NO_CREDENTIAL

# The escape hatch, for the test matrix and for a reader on a metered plan.
: > "$STUB_LOG"
_hs=$(mktemp -d)/hub; mkdir -p "$_hs"
KB_SKIP_HUB_PROOF=1 kb_point_hermes_at_hub "$_hs" >/dev/null 2>&1
t "KB_SKIP_HUB_PROOF spends no request" "$(grep -c -- '-z' "$STUB_LOG")" "0"
t "but still sets the folder" "$(grep -c 'config set terminal.cwd' "$STUB_LOG")" "1"

t "a folder that is not there is unavailable, not a failed read" \
  "$(kb_hermes_reads_hub "$_hb/no-such-hub")" "unavailable"

# And with no Hermes at all, which is every machine before the install finishes.
KB_HERMES_BIN="$_hb/bin/no-such-hermes"
out="$(kb_point_hermes_at_hub "$_hh" 2>&1)"; _rc=$?
t "no Hermes on the machine is not a failure" "$_rc" "0"
t "and it says so plainly instead of going quiet" \
  "$(printf '%s' "$out" | grep -c 'Hermes is not on this machine yet')" "1"
KB_HERMES_BIN="$_hb/bin/hermes"

unset KB_HERMES_BIN STUB_LOG STUB_CWDFILE STUB_ELSEWHERE
rm -rf "$_hb"

echo
echo "== the leash, translated rather than renamed"
#
# The shape of these rules was measured on stock Hermes 0.21.0 before any of it was
# written, because an approvals.deny entry is a glob over the WHOLE normalised command
# and the obvious spelling stops nothing: "iptables" does not even deny `iptables -F`.
# The stub below does the same glob matching with `case`, so a rule that would be inert
# on the real thing is inert here too.
_ap=$(mktemp -d); mkdir -p "$_ap/bin"
cat > "$_ap/bin/hermes" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
rules() {
  [ -s "$STUB_DENY" ] || return 0
  sed 's/^\[//; s/\]$//; s/","/\
/g; s/"//g' "$STUB_DENY"
}
if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "approvals.deny" ]; then
  # QUOTED, the way a real YAML writer hands them back. Every rule starts with a *,
  # which YAML reads as an alias, so Hermes quotes all of them. This stub echoed them
  # back bare, and that is exactly why it agreed with a merge that could not read them:
  # on the real box a second run added all eighteen again, quote characters and all.
  if [ -s "$STUB_DENY" ]; then rules | sed "s/^/- '/; s/\$/'/"; else
    echo "Config key not set: approvals.deny"; exit 1; fi
fi
if [ "$1" = "config" ] && [ "$2" = "set" ] && [ "$3" = "approvals.deny" ]; then
  printf '%s' "$4" > "$STUB_DENY"
fi
if [ "$1" = "auth" ] && [ "$2" = "list" ]; then echo "openai-codex (1 credentials):"; fi
if [ "$1" = "approvals" ] && [ "$2" = "test" ]; then
  shift 2; [ "$1" = "--" ] && shift
  cmd="$*"
  [ "${STUB_TOOTIGHT:-0}" = "1" ] && [ "$cmd" = "git status" ] && exit 2
  [ "${STUB_TOOTIGHT:-0}" = "2" ] && exit 0
  rules | while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$cmd" in $p) exit 9 ;; esac
  done
  [ $? -eq 9 ] && exit 3
  exit 0
fi
exit 0
STUB
chmod +x "$_ap/bin/hermes"
export KB_HERMES_BIN="$_ap/bin/hermes"
export STUB_LOG="$_ap/calls.log" STUB_DENY="$_ap/deny.json"
: > "$STUB_LOG"

out="$(kb_hermes_approvals 2>&1)"; _rc=$?
t "the leash goes on, and says so" "$_rc" "0"
t "every shipped rule reaches the config" \
  "$(kb_hermes_deny_rules | while IFS= read -r r; do grep -qF -- "$r" "$STUB_DENY" || echo miss; done | grep -c .)" "0"
t "approvals.mode is never written, because the shipped default is the right one" \
  "$(grep -c 'approvals.mode' "$STUB_LOG")" "0"
t "and no allowlist is written, because Hermes already allows the kit's own work" \
  "$(grep -c 'command_allowlist' "$STUB_LOG")" "0"
t "the check runs both ways, not just the scary one" \
  "$(printf '%s' "$out" | grep -c 'checked both ways')" "1"

# Twice equals once.
: > "$STUB_LOG"
kb_hermes_approvals >/dev/null 2>&1
t "a second run adds nothing" "$(grep -c 'config set approvals.deny' "$STUB_LOG")" "0"

# A rule somebody added themselves is not thrown away. `hermes config set` REPLACES a
# list, so without read, merge, write this is how a reader loses their own rule.
printf '%s' '["*my own rule*"]' > "$STUB_DENY"
: > "$STUB_LOG"
kb_hermes_approvals >/dev/null 2>&1
t "a rule the reader added themselves survives" \
  "$(grep -c 'my own rule' "$STUB_DENY")" "1"
t "and the shipped rules are there beside it" \
  "$(grep -c 'ufw --force reset' "$STUB_DENY")" "1"

# THE TWO WAYS THE SELF-CHECK EARNS ITS PLACE.
: > "$STUB_DENY"
STUB_TOOTIGHT=2; export STUB_TOOTIGHT   # nothing is ever refused
out="$(kb_hermes_approvals 2>&1)"; _rc=$?
t "rules that do not bite are reported, not celebrated" "$_rc" "1"
t "and the message says what it means" \
  "$(printf '%s' "$out" | grep -c 'not biting')" "1"
: > "$STUB_DENY"
STUB_TOOTIGHT=1                          # even git status would stop to ask
out="$(kb_hermes_approvals 2>&1)"; _rc=$?
t "rules that went too far are caught as well" "$_rc" "1"
t "and that message says what it means too" \
  "$(printf '%s' "$out" | grep -c 'went too far')" "1"
unset STUB_TOOTIGHT

# A machine with no Hermes on it yet, which is every machine partway through an install.
KB_HERMES_BIN="$_ap/bin/no-such-hermes"
out="$(kb_hermes_approvals 2>&1)"; _rc=$?
t "no Hermes is not a failure here either" "$_rc" "0"
t "and it says there is nothing to give rules to" \
  "$(printf '%s' "$out" | grep -c 'no rules to give it')" "1"

# THE VERSION THAT STORES THE LIST AS TEXT. Hermes 0.20.0 does not parse a JSON
# list on `config set`: it stores the whole text as ONE STRING, its readers
# ignore a string, and the string echoes back through `config get` so a blind
# merge nests it deeper on every run. Measured on the book's own rehearsal
# server: the second run wrapped the first run's entire JSON inside the new
# list. The stub stores verbatim and echoes RAW, exactly as that version does.
cat > "$_ap/bin/hermes-old" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
if [ "$1" = "config" ] && [ "$2" = "get" ] && [ "$3" = "approvals.deny" ]; then
  if [ -s "$STUB_DENY" ]; then cat "$STUB_DENY"; echo; else
    echo "Config key not set: approvals.deny"; exit 1; fi
fi
if [ "$1" = "config" ] && [ "$2" = "set" ] && [ "$3" = "approvals.deny" ]; then
  printf -- '%s' "$4" > "$STUB_DENY"
fi
if [ "$1" = "auth" ] && [ "$2" = "list" ]; then echo "openai-codex (1 credentials):"; fi
exit 0
STUB
chmod +x "$_ap/bin/hermes-old"
KB_HERMES_BIN="$_ap/bin/hermes-old"; export KB_HERMES_BIN
: > "$STUB_DENY"; : > "$STUB_LOG"
out="$(kb_hermes_approvals 2>&1)"; _rc=$?
t "a Hermes that stores the rules as text is caught, not celebrated" "$_rc" "1"
t "and the message says the leash is NOT on" \
  "$(printf '%s' "$out" | grep -c 'NOT on')" "1"
_sz1=$(wc -c < "$STUB_DENY")
kb_hermes_approvals >/dev/null 2>&1
t "a second run does not nest the list deeper" "$(wc -c < "$STUB_DENY" | tr -d ' ')" "$(printf '%s' "$_sz1" | tr -d ' ')"

unset KB_HERMES_BIN STUB_LOG STUB_DENY
rm -rf "$_ap"

echo
echo "== the always-on half: the gateway, the clock, and signing in"
#
# The one fact these all turn on, measured in Run 2 rather than read: the clock lives
# inside the gateway process, so a job with no live gateway does not fire, and nothing
# is ever caught up afterwards. Every case below exists to stop the kit implying
# otherwise.
_gw=$(mktemp -d); mkdir -p "$_gw/bin"
cat > "$_gw/bin/hermes" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
if [ "$1" = "gateway" ] && [ "$2" = "status" ]; then
  case "${STUB_GW:-running}" in
    running) echo "Active: active (running)"; echo "* System gateway service is running" ;;
    absent)  echo "Gateway service is not installed" ;;
    *)       echo "Active: failed (Result: exit-code)" ;;
  esac
fi
if [ "$1" = "gateway" ] && [ "$2" = "install" ]; then
  [ "${STUB_GW_INSTALL_FAILS:-0}" = "1" ] || STUB_GW=running
  echo "$STUB_GW" > "$STUB_GWFILE"
fi
if [ "$1" = "cron" ] && [ "$2" = "list" ]; then
  [ -s "$STUB_JOBS" ] && sed 's/^/    Name:      /' "$STUB_JOBS"
fi
if [ "$1" = "cron" ] && [ "$2" = "create" ]; then
  n=""; while [ $# -gt 0 ]; do [ "$1" = "--name" ] && n="$2"; shift; done
  [ -n "$n" ] && echo "$n" >> "$STUB_JOBS"
fi
if [ "$1" = "auth" ] && [ "$2" = "list" ]; then
  [ -s "$STUB_AUTH" ] && cat "$STUB_AUTH"
fi
if [ "$1" = "auth" ] && [ "$2" = "add" ]; then
  [ "${STUB_SIGNIN_FAILS:-0}" = "1" ] || echo "$3 (1 credentials):" >> "$STUB_AUTH"
fi
exit 0
STUB
chmod +x "$_gw/bin/hermes"
export KB_HERMES_BIN="$_gw/bin/hermes"
export STUB_LOG="$_gw/calls.log" STUB_JOBS="$_gw/jobs.txt" STUB_AUTH="$_gw/auth.txt"
export STUB_GWFILE="$_gw/gw.txt"
: > "$STUB_LOG"; : > "$STUB_JOBS"; : > "$STUB_AUTH"

t "a gateway that is up reads as running"   "$(STUB_GW=running kb_gateway_state)" "running"
t "a gateway that was stopped reads as stopped, not as running" \
  "$(STUB_GW=failed kb_gateway_state)" "stopped"
t "and one that was never installed says so"  "$(STUB_GW=absent kb_gateway_state)"  "absent"
KB_HERMES_BIN="$_gw/bin/no-such-hermes"
t "no Hermes at all is unavailable, not stopped" "$(kb_gateway_state)" "unavailable"
KB_HERMES_BIN="$_gw/bin/hermes"

# A CLEAN STOP LEAVES THE UNIT `failed`, measured. So `stopped` has to come from a
# reading that cannot tell those apart, and the kit must never call `failed` a crash.
t "a failed unit is reported as stopped, because a clean stop looks exactly like one" \
  "$(STUB_GW=failed kb_gateway_state)" "stopped"

# The gateway install. What matters is whether it is RUNNING afterwards, never the
# exit status of the install command.
#
# --system writes into /etc/systemd/system, so the function refuses to run as anybody
# but root. This suite is not root and must never be, so kb_is_root is stood in for
# just these cases and put back straight afterwards. The refusal itself is checked
# separately below, with the real one.
eval "_real_kb_is_root() $(declare -f kb_is_root | sed "1d")"
kb_is_root() { return 0; }
: > "$STUB_LOG"
out="$(STUB_GW=running kb_install_gateway someuser 2>&1)"; _rc=$?
t "the generator is asked for a system service, run as the named account" \
  "$(grep -c 'gateway install --system --run-as-user someuser --start-on-login --force' "$STUB_LOG")" "1"
t "and it is checked by asking whether it is running" \
  "$(grep -c 'gateway status' "$STUB_LOG")" "1"
t "an install that ends up running succeeds" "$_rc" "0"
out="$(STUB_GW=failed kb_install_gateway someuser 2>&1)"; _rc=$?
t "an install that ends up not running is a failure, whatever the command returned" "$_rc" "1"
t "and the reader is told nothing will fire until it is up" \
  "$(printf '%s' "$out" | grep -c 'will fire')" "1"

# And the refusal, with the real kb_is_root back in place. A reader who runs the
# server steps as themselves gets told so, rather than a permission error from
# somewhere inside systemd.
kb_is_root() { _real_kb_is_root; }
if ! kb_is_root; then
  : > "$STUB_LOG"
  out="$(kb_install_gateway someuser 2>&1)"; _rc=$?
  t "installing the service as a normal user is refused, not attempted" "$_rc" "1"
  t "and nothing was run" "$(grep -c 'gateway install' "$STUB_LOG")" "0"
  t "with the reason named" "$(printf '%s' "$out" | grep -c 'has to be installed as root')" "1"
else
  echo "  skip  the not-root case needs a session that is not root"
fi

# The clock.
_ch=$(mktemp -d)/hub; mkdir -p "_ch" 2>/dev/null; mkdir -p "$_ch"
: > "$STUB_LOG"; : > "$STUB_JOBS"
out="$(STUB_GW=running kb_cron_job "$_ch" morning-brief "0 7 * * *" "write my brief" telegram 2>&1)"; _rc=$?
t "a job the kit creates always carries --workdir, or it has no house rules at all" \
  "$(grep -c -- "--workdir $(cd "$_ch" && pwd -P)" "$STUB_LOG")" "1"
t "the schedule and the name go in too" \
  "$(grep -c -- '--name morning-brief' "$STUB_LOG")" "1"
t "and the delivery target when one is given" \
  "$(grep -c -- '--deliver telegram' "$STUB_LOG")" "1"
t "scheduling a job on a live gateway succeeds" "$_rc" "0"

# `hermes cron run` fires a job by hand with no gateway at all, so an installer that
# used it to prove the schedule works would be reporting on something it never tested.
t "the installer never fires the job to prove the schedule works" \
  "$(grep -c 'cron run' "$STUB_LOG")" "0"

# Twice equals once, or a reader gets their morning brief twice.
: > "$STUB_LOG"
STUB_GW=running kb_cron_job "$_ch" morning-brief "0 7 * * *" "write my brief" telegram >/dev/null 2>&1
t "a second run does not make a second job" "$(grep -c 'cron create' "$STUB_LOG")" "0"
t "and there is still exactly one" "$(grep -c . "$STUB_JOBS")" "1"

# THE HONEST PART, and the reason this function is not just a wrapper.
: > "$STUB_JOBS"
out="$(STUB_GW=failed kb_cron_job "$_ch" nightly "0 2 * * *" "tidy up" 2>&1)"; _rc=$?
t "a job on a machine with no live gateway is reported, not celebrated" "$_rc" "1"
t "the reader is told it will not fire" \
  "$(printf '%s' "$out" | grep -c 'will NOT fire')" "1"
t "and that a missed slot is gone rather than queued" \
  "$(printf '%s' "$out" | grep -c 'never caught up')" "1"
# The Chapter 29 run found the wording wrong for the common server case: the
# installer had JUST installed the gateway, it was stopped, and the reader was told
# to install it. A stopped gateway is started; only a missing one is installed.
t "a gateway that is stopped is told to START it" \
  "$(printf '%s' "$out" | grep -c 'start the gateway')" "1"
t "and not to install one that is already there" \
  "$(printf '%s' "$out" | grep -c 'install the gateway')" "0"
: > "$STUB_JOBS"
out="$(STUB_GW=absent kb_cron_job "$_ch" nightly "0 2 * * *" "tidy up" 2>&1)"; _rc=$?
t "a gateway that was never installed is told to install it" \
  "$(printf '%s' "$out" | grep -c 'install the gateway')" "1"
t "and a job on a machine with no gateway at all is still a failure" "$_rc" "1"
t "the deny-by-default boundary is stated rather than quietly widened" \
  "$(STUB_GW=running kb_cron_job "$_ch" j2 "0 3 * * *" "x" 2>&1 | grep -c 'refused a dangerous command')" "1"

# Signing in.
#
# Hermes buffers the device code when stdout is not a tty, so the real function puts
# `script` in front of it to make one. Git Bash ships no script(1), so without a
# stand-in every case below would fall through to the "no terminal here" branch and
# test nothing. This one just runs what it is handed, which is all the real one does
# that matters here.
printf '#!/bin/sh
sh -c "$2"
' > "$_gw/bin/script"
chmod +x "$_gw/bin/script"
_oldpath="$PATH"; PATH="$_gw/bin:$PATH"; export PATH
: > "$STUB_AUTH"
t "a provider nobody has connected is not connected" \
  "$(kb_hermes_has_provider openai-codex && echo yes || echo no)" "no"
printf 'openai-codex (1 credentials):\n' > "$STUB_AUTH"
t "and one that is, is"  "$(kb_hermes_has_provider openai-codex && echo yes || echo no)" "yes"
t "a different provider is not confused for it" \
  "$(kb_hermes_has_provider openrouter && echo yes || echo no)" "no"
: > "$STUB_LOG"
out="$(kb_hermes_signin openai-codex 2>&1)"; _rc=$?
t "an account already connected is left alone" "$(grep -c 'auth add' "$STUB_LOG")" "0"
t "and saying so is not a failure" "$_rc" "0"

: > "$STUB_AUTH"; : > "$STUB_LOG"
out="$(kb_hermes_signin openai-codex 2>&1)"; _rc=$?
t "the sign-in uses auth add with the device code flow" \
  "$(grep -c 'auth add openai-codex --type oauth --no-browser' "$STUB_LOG")" "1"
t "and never the deprecated login command" "$(grep -cx 'login' "$STUB_LOG")" "0"
t "the fifteen minute window is said out loud" \
  "$(printf '%s' "$out" | grep -c 'fifteen minutes')" "1"
t "and that running out is safe to just repeat" \
  "$(printf '%s' "$out" | grep -c 'nothing is broken')" "1"
t "a sign-in that worked reports success" "$_rc" "0"

: > "$STUB_AUTH"
STUB_SIGNIN_FAILS=1; export STUB_SIGNIN_FAILS
out="$(kb_hermes_signin openai-codex 2>&1)"; _rc=$?
t "a sign-in that did not take is reported" "$_rc" "1"
t "with the exact command to run again" \
  "$(printf '%s' "$out" | grep -c 'auth add openai-codex --type oauth --no-browser')" "1"
unset STUB_SIGNIN_FAILS

PATH="$_oldpath"; export PATH
unset KB_HERMES_BIN STUB_LOG STUB_JOBS STUB_AUTH STUB_GWFILE STUB_GW
rm -rf "$_gw"

echo
echo "== one room, one name"
#
# THE BUG THESE EXIST FOR. Measured on a real existing hub during Run 2: the top-up
# found no profile/, so it copied the starter's in beside a context/ that already held
# the same four filenames. The next run then warned "you have both, delete the empty
# one" at a reader whose folders both had four files in them. The installer built the
# duplicate and then complained about it, and the complaint was not true either.

_rm=$(mktemp -d)
mkdir -p "$_rm/h1/context"
t "a hub with context/ is told profile/ is the same room"  "$(kb_room_twin "$_rm/h1" profile)" "context"
t "and the question answers in the other direction too"    "$(kb_room_twin "$_rm/h1" context)" ""
mkdir -p "$_rm/h2/observations"
t "memory/ and observations/ are the same pair"            "$(kb_room_twin "$_rm/h2" memory)" "observations"
t "a room with no older name has no twin"                  "$(kb_room_twin "$_rm/h1" rules)"   ""
t "and neither does a hub that has neither spelling"       "$(kb_room_twin "$_rm/h2" profile)" ""

# The rename, which is what SHOULD happen to a hub that only has the old name.
_r1=$(mktemp -d); mkdir -p "$_r1/context"; : > "$_r1/context/about-me.md"
kb_migrate_folder_names "$_r1" >/dev/null 2>&1
t "context/ becomes profile/ rather than gaining a sibling" \
  "$([ -d "$_r1/profile" ] && [ ! -d "$_r1/context" ] && echo yes)" "yes"
t "and the reader's file came with it" \
  "$([ -f "$_r1/profile/about-me.md" ] && echo yes)" "yes"

# THE LINE THAT MADE THE DUPLICATE. It used to be an unconditional mkdir.
_r2=$(mktemp -d); mkdir -p "$_r2/context" "$_r2/profile"; : > "$_r2/context/a.md"; : > "$_r2/profile/b.md"
out="$(kb_migrate_folder_names "$_r2" 2>&1)"
t "a hub that really has both keeps both, untouched" \
  "$([ -f "$_r2/context/a.md" ] && [ -f "$_r2/profile/b.md" ] && echo yes)" "yes"
t "and it is never told to delete the empty one, because neither is empty" \
  "$(printf '%s' "$out" | grep -c 'delete the empty one')" "0"
t "it is told what is actually in each" \
  "$(printf '%s' "$out" | grep -c '1 inside')" "1"
t "and which one the assistant actually reads" \
  "$(printf '%s' "$out" | grep -c 'your assistant reads profile/')" "1"

# rules/ has never had another name, so it is always made.
_r3=$(mktemp -d); mkdir -p "$_r3/context"
kb_migrate_folder_names "$_r3" >/dev/null 2>&1
t "rules/ is made whatever else is going on" "$([ -d "$_r3/rules" ] && echo yes)" "yes"

# The top-up. A local starter repo, so this stays off the network like everything else
# in this file.
_st=$(mktemp -d)/starter; mkdir -p "$_st/starter-hub/profile" "$_st/starter-hub/observations"
: > "$_st/starter-hub/profile/about-me.md"
: > "$_st/starter-hub/observations/MEMORY.md"
: > "$_st/starter-hub/AGENTS.md"
git -C "$_st" init -q 2>/dev/null
git -C "$_st" add -A >/dev/null 2>&1
git -C "$_st" -c user.email=t@t -c user.name=t commit -q -m starter >/dev/null 2>&1

_r4=$(mktemp -d); mkdir -p "$_r4/context"; : > "$_r4/context/about-me.md"
kb_copy_starter_hub "$_r4" "$_st" starter-hub >/dev/null 2>&1
t "the top-up does NOT drop profile/ beside an existing context/" \
  "$([ -d "$_r4/profile" ] && echo made || echo no)" "no"
t "the reader's own room is untouched" \
  "$([ -f "$_r4/context/about-me.md" ] && echo yes)" "yes"
t "and everything that is genuinely new still arrives" \
  "$([ -f "$_r4/AGENTS.md" ] && echo yes)" "yes"
t "including the other room, which this hub does not have under either name" \
  "$([ -d "$_r4/observations" ] && echo yes)" "yes"

# And a hub with neither spelling gets the room, or the guard has gone too far.
_r5=$(mktemp -d)
kb_copy_starter_hub "$_r5" "$_st" starter-hub >/dev/null 2>&1
t "a hub with neither name still gets profile/" "$([ -d "$_r5/profile" ] && echo yes)" "yes"

rm -rf "$_rm"

echo
echo "== a kit ships products, not its own test suite"
#
# Measured on a real install during Run 2: test-notebook-sync.sh and
# test-prompt-archive.sh were copied onto the reader's PATH beside hub-due and
# hub-check-keys.
_tk=$(mktemp -d)/kit; mkdir -p "$_tk/tools"
for _f in due.js check-keys.js hub-notebook-sync test-notebook-sync.sh test-prompt-archive.sh README.md; do
  printf '#!/bin/sh\necho %s\n' "$_f" > "$_tk/tools/$_f"
done
git -C "$_tk" init -q 2>/dev/null
git -C "$_tk" add -A >/dev/null 2>&1
git -C "$_tk" -c user.email=t@t -c user.name=t commit -q -m tools >/dev/null 2>&1

_th=$(mktemp -d); _thome=$(mktemp -d)
HOME="$_thome" kb_install_hub_tools "$_th" "$_tk" >/dev/null 2>&1
t "the products a reader types are installed" \
  "$([ -f "$_thome/.local/bin/due.js" ] && [ -f "$_thome/.local/bin/hub-notebook-sync" ] && echo yes)" "yes"
t "and the kit's own tests are NOT" \
  "$(find "$_thome/.local/bin" -name 'test-*' 2>/dev/null | grep -c .)" "0"
t "the README does not become a command either" \
  "$([ -f "$_thome/.local/bin/README.md" ] && echo shipped || echo no)" "no"
t "the launcher for a real command is still made" \
  "$([ -f "$_thome/.local/bin/hub-due" ] && echo yes)" "yes"

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
