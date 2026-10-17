#!/usr/bin/env bash
# What a reader has after install-godspeed.sh on Linux or a Mac, checked against the public
# guide (content/guide/*.md of godspeedmissioncontrol.com, release godspeed-v2-integrated-2026-10-16-2).
# Evidence only: every command and its whole answer are printed, nothing is hidden, and this
# script never fails the job by itself (the verification is read from the log afterwards).
#
#   bash .github/guide-verify/unix-checks.sh linux|mac
set +e
PLATFORM=${1:-linux}
EV=${EVIDENCE:-$PWD/evidence}; mkdir -p "$EV"
MC="$HOME/godspeed-v2"
RUNTIME="$MC/.godspeed/integrated-runtime"
export PATH="$HOME/.local/bin:$PATH"   # what the line the installer adds to .bashrc does in a new terminal

section() { printf '\n\n########## %s\n' "$*"; }
# t "<command>"  prints the command, its whole answer and its exit code; at most 180 s.
t() {
  printf '\n$ %s\n' "$1"
  perl -e 'alarm shift @ARGV; exec @ARGV' "${TMO:-180}" bash -c "$1" 2>&1
  printf '[exit %s]\n' "$?"
}
have() { if [ -e "$1" ]; then echo "present  $1"; else echo "ABSENT   $1"; fi; }

section "health address (check-it-works: The health address)"
t "curl -s http://127.0.0.1:47831/health; echo"
t "curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' http://127.0.0.1:47831/"
t "curl -s http://127.0.0.1:47831/dashboard | grep -o 'id=\"root\"' | head -1"
t "curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:47831/dashboard/settings"

if [ "$PLATFORM" = linux ]; then
  section "the notebook service (install-mac-linux: On Linux; check-it-works: On Linux)"
  t "systemctl status godspeed-integrated-notebook.service --no-pager"
  t "systemctl is-enabled godspeed-integrated-notebook.service; systemctl is-active godspeed-integrated-notebook.service"
  t "cat /etc/systemd/system/godspeed-integrated-notebook.service"
  t "systemctl --user status godspeed-integrated-notebook.service --no-pager"
  t "journalctl -u godspeed-integrated-notebook.service -n 50 --no-pager"
  t "systemctl status godspeed-https.service --no-pager"
  t "ls -la /etc/systemd/system | grep -i godspeed"
fi

section "which release (updates-and-versions: Your release on a Mac or Linux computer)"
t "cat ~/godspeed-v2/.godspeed/integrated-runtime/version"
t "cat ~/godspeed-v2/.godspeed/integrated-runtime/previous-version"
t "grep GODSPEED_PRODUCT_REF= install-godspeed.sh"

section "folders (folders-and-settings, install-mac-linux: What you have now)"
t "ls -la ~/godspeed-v2"
for f in AGENTS.md CLAUDE.md README.md FULL-ALPHA.md procedures.md decisions.md .mcp.json .gitignore .gitattributes \
         profile/about-me.md profile/people.md profile/projects.md profile/voice.md rules skills assistant/extra-instructions.md \
         inbox dev secrets/expires.txt notebook notebook/_system observations observations/MEMORY.md goals goals/research work \
         forecasts ideas due world prompts/archive prompts/library coach routines assistant-state conflicts .godspeed .claude \
         .godspeed/food/bls-4.0/NOTICE.md .godspeed/backups .godspeed/backup-status.json; do have "$MC/$f"; done
t "cat ~/godspeed-v2/CLAUDE.md"
t "ls ~/godspeed-v2/rules; ls ~/godspeed-v2/rules | wc -l"
t "ls -d ~/godspeed-v2/skills/*/ | wc -l; ls ~/godspeed-v2/skills/*/SKILL.md | wc -l"
t "ls ~/godspeed-v2/skills"
t "ls -la ~/godspeed-v2/.godspeed"
t "ls -la ~/godspeed-v2/.godspeed/integrated-runtime"
t "ls ~/godspeed-v2/.godspeed/integrated-runtime/versions ~/godspeed-v2/.godspeed/integrated-runtime/runtime ~/godspeed-v2/.godspeed/integrated-runtime/backups ~/godspeed-v2/.godspeed/integrated-runtime/media"
t "ls ~/godspeed-v2/notebook; ls ~/godspeed-v2/notebook/_system | head"
t "git -C ~/godspeed-v2 log --oneline -5; git -C ~/godspeed-v2 remote -v"
t "sed -E 's/((KEY|TOKEN|SECRET|PASS|CODE)[A-Z_]*=).*/\1(hidden)/' ~/.godspeed/device.env"
t "ls -la ~/.godspeed"
t "ls -la ~/.local/bin"
t "ls -la ~/.hermes | head -40"
t "command -v hermes; hermes --version"
t "crontab -l"
t "tail -5 ~/.bashrc; ls -la ~ | grep -E 'rc|profile'"
t "grep -n 'local/bin' ~/.bashrc ~/.zshrc ~/.zprofile ~/.profile ~/.bash_profile 2>/dev/null"

section "are the commands found in a NEW terminal (terminal-commands: Where the commands are)"
t "env -i HOME=\$HOME USER=\$USER TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin bash -ic 'command -v mc-due hermes' 2>&1 | grep -v 'no job control\|cannot set terminal'"
t "env -i HOME=\$HOME USER=\$USER TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin bash -lc 'command -v mc-due hermes'"
if [ "$PLATFORM" = mac ]; then
  t "env -i HOME=\$HOME USER=\$USER TERM=xterm PATH=/usr/bin:/bin:/usr/sbin:/sbin zsh -lic 'command -v mc-due hermes; echo PATH=\$PATH'"
fi
t "command -v godspeed || echo 'no command named godspeed'"

section "terminal commands (terminal-commands.md), in the order the page shows them"
export GODSPEED_DIR="$MC"
cd "$MC" || true
t "mc-due"
t "mc-due --help"
t "mc-due today"
t "mc-due add nodate --title 'No day' --done-when 'x'"
t "mc-due add costly --title 'Costly' --to 2026-12-01"
t "mc-due add dentist --title 'Book the dentist' --target 2026-11-15 --done-when 'an appointment is booked'"
t "mc-due"
t "mc-due drop dentist"
t "mc-due done dentist --evidence 'booked for 20 November'"
t "ls ~/godspeed-v2/world/events ~/godspeed-v2/due"
t "mc-due check"
t "mc-due state"
t "mc-goals help"
t "mc-goals list"
t "mc-goals file --kind outcome --title 'Run a 10 km race' --source 'said in chat, 2026-10-17' --area health --measure 'a finished 10 km race'"
t "mc-goals adopt run-a-10-km-race"
t "mc-goals adopt run-a-10-km-race --why 'I said yes on 2026-10-17'"
t "mc-goals list"
t "mc-goals show run-a-10-km-race"
t "mc-goals tree"
t "mc-goals attention"
t "mc-goals may run-a-10-km-race"
t "mc-goals allow run-a-10-km-race --kind payment --what 'pay the race fee' --per-week 1 --words 'ok'"
t "mc-work help"
t "mc-work list"
t "mc-work going-out"
t "mc-work went-out"
t "mc-work stop W-20261017-01 --words 'not this one'"
t "mc-forecast help"
t "mc-forecast list"
t "mc-forecast score"
t "mc-compile-rules --check"
t "mc-check-keys"
t "mc-check-built-on"
t "mc-check-built-on --claim nonsense"
t "mc-search dentist"
t "mc-search zzqqxx-nothing"
t "mc-prompt-archive search zzqqxx-nothing"
t "mc-prompt-archive stats"
t "mc-prompt-archive sources"
t "mc-prompt-archive --dry-run"
t "mc-prompt-harvest --verbose --no-push"
t "mc-mail"
t "mc-mail status"
t "mc-mail pending"
t "mc-mail nonsense-word"
t "mc-mail setup --check"
t "mc-run --list"
t "mc-run no-such-recipe --prompt x"
t "mc-run --bogus"
t "mc-decide --dry-run"
t "mc-work-run --dry-run"
t "mc-research --dry-run"
TMO=60 t "mc-observed-state"
t "mc-menerio-connect --check"
t "command -v godspeed-browser || echo 'godspeed-browser: not installed (no browser was lent)'"
t "hermes cron list"
t "hermes cron status"
t "ls ~/.hermes/bin 2>/dev/null | head -60"

section "the notebook's own command (notebook-command.md: Mac and Linux block, then each command)"
cd "$HOME" || true
cat > "$EV/nb-env.sh" <<'EOF'
export GODSPEED_WORKSPACE="$HOME/godspeed-v2"
RUNTIME="$GODSPEED_WORKSPACE/.godspeed/integrated-runtime"
export GODSPEED_MEDIA_ROOT="$RUNTIME/media"
NODE="$(ls "$RUNTIME"/runtime/node-v22.19.0-*/bin/node)"
NOTEBOOK="$RUNTIME/versions/$(cat "$RUNTIME/version")/notebook/bin/godspeed.mjs"
EOF
NB=". '$EV/nb-env.sh';"
t "$NB echo NODE=\$NODE; echo NOTEBOOK=\$NOTEBOOK; ls -la \"\$NODE\" \"\$NOTEBOOK\""
t "$NB \"\$NODE\" \"\$NOTEBOOK\" validate"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" export > notebook-export.json; head -c 300 notebook-export.json; echo; \"\$NODE\" -e 'const e=require(\"./notebook-export.json\");console.log(\"format\",e.format,\"records\",e.records.length)'"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" backup \"\$HOME/godspeed-backups/2026-10-17\""
t "$NB \"\$NODE\" \"\$NOTEBOOK\" backup \"\$HOME/godspeed-backups/2026-10-17\""
t "ls -la ~/godspeed-backups/2026-10-17; head -c 400 ~/godspeed-backups/2026-10-17/backup.json; echo"
t "$NB mkdir -p \"\$HOME/restored/workspace\" \"\$HOME/restored/media\"
GODSPEED_WORKSPACE=\"\$HOME/restored/workspace\" GODSPEED_MEDIA_ROOT=\"\$HOME/restored/media\" \"\$NODE\" \"\$NOTEBOOK\" restore \"\$HOME/godspeed-backups/2026-10-17\""
t "ls -la ~/restored/workspace | head -30; ls ~/restored/workspace/notebook | head"
t "$NB GODSPEED_WORKSPACE=\"\$HOME/restored/workspace\" GODSPEED_MEDIA_ROOT=\"\$HOME/restored/media\" \"\$NODE\" \"\$NOTEBOOK\" restore \"\$HOME/godspeed-backups/2026-10-17\""
t "$NB mkdir -p \"\$HOME/r2/workspace\" \"\$HOME/r2/media\"; echo x > \"\$HOME/r2/media/photo.jpg\"; GODSPEED_WORKSPACE=\"\$HOME/r2/workspace\" GODSPEED_MEDIA_ROOT=\"\$HOME/r2/media\" \"\$NODE\" \"\$NOTEBOOK\" restore \"\$HOME/godspeed-backups/2026-10-17\""
t "$NB mkdir -p \"\$HOME/r3/workspace\" \"\$HOME/r3/media\" \"\$HOME/not-a-backup\"; GODSPEED_WORKSPACE=\"\$HOME/r3/workspace\" GODSPEED_MEDIA_ROOT=\"\$HOME/r3/media\" \"\$NODE\" \"\$NOTEBOOK\" restore \"\$HOME/not-a-backup\""
t "$NB cp -R \"\$HOME/godspeed-backups/2026-10-17\" \"\$HOME/damaged-backup\"; f=\$(cd \"\$HOME/damaged-backup\" && find . -type f -name '*.md' | head -1); echo \"changing \$f\"; echo tampered >> \"\$HOME/damaged-backup/\$f\"; mkdir -p \"\$HOME/r4/workspace\" \"\$HOME/r4/media\"; GODSPEED_WORKSPACE=\"\$HOME/r4/workspace\" GODSPEED_MEDIA_ROOT=\"\$HOME/r4/media\" \"\$NODE\" \"\$NOTEBOOK\" restore \"\$HOME/damaged-backup\""
t "$NB \"\$NODE\" \"\$NOTEBOOK\" import notebook-export.json"
t "$NB mkdir -p \"\$HOME/imported\"; GODSPEED_WORKSPACE=\"\$HOME/imported\" \"\$NODE\" \"\$NOTEBOOK\" import notebook-export.json"
t "$NB GODSPEED_WORKSPACE=\"\$HOME/imported\" \"\$NODE\" \"\$NOTEBOOK\" import notebook-export.json"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" prune-backups"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" prune-backups \"\$RUNTIME/backups\" --made \"\$HOME/godspeed-backups/2026-10-17\" --keep 3"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" sync folder"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" assistant profiles"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" assistant select no-such-profile"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" food-table status"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" memory search dentist"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" world close --dry-run"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" convert-notebook --dry-run"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" init"
t "$NB \"\$NODE\" \"\$NOTEBOOK\""
t "$NB \"\$NODE\" \"\$NOTEBOOK\" no-such-command"
t "$NB env -u GODSPEED_WORKSPACE \"\$NODE\" \"\$NOTEBOOK\" validate"
t "$NB \"\$NODE\" \"\$NOTEBOOK\" workspace-move plan \"\$HOME/moved\" \"\$HOME/no-installation.json\""
t "ls ~/godspeed-v2/.godspeed/backups 2>/dev/null; cat ~/godspeed-v2/.godspeed/backup-status.json 2>/dev/null"
echo
echo "unix-checks done"
