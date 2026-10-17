#!/usr/bin/env bash
# The guide's "Uninstall on a Mac or Linux computer" (uninstall.md), step by step as written,
# then everything of Godspeed Mission Control and Hermes that is still on the machine.
#   bash .github/guide-verify/unix-uninstall.sh linux|mac
set +e
PLATFORM=${1:-linux}
section() { printf '\n\n########## %s\n' "$*"; }
t() { printf '\n$ %s\n' "$1"; perl -e 'alarm shift @ARGV; exec @ARGV' 120 bash -c "$1" 2>&1; printf '[exit %s]\n' "$?"; }
leftovers() {
  t "ls -la ~ | grep -i -E 'godspeed|hermes|\\.local|\\.config'"
  t "find ~ -maxdepth 4 \\( -iname '*godspeed*' -o -iname '*hermes*' -o -iname 'mc-*' \\) -not -path '*/work/*' -not -path '*/actions-runner/*' -not -path '*/runners/*' 2>/dev/null | grep -v -E '/(\\.cache/ms-playwright|go/pkg)/' | head -80"
  t "ls -la ~/.local/bin 2>/dev/null"
  t "crontab -l"
  t "curl -s -m 5 http://127.0.0.1:47831/health || echo 'nothing answers on 127.0.0.1:47831'"
  t "ps aux | grep -i -E 'start.mjs|supervise.mjs|godspeed|hermes' | grep -v grep"
  if [ "$PLATFORM" = linux ]; then
    t "ls /etc/systemd/system | grep -i godspeed; ls ~/.config/systemd/user 2>/dev/null | grep -i godspeed; systemctl list-units --all --no-pager | grep -i godspeed"
    t "ls -la /etc/caddy 2>/dev/null"
  else
    t "ls ~/Library/LaunchAgents 2>/dev/null | grep -i godspeed; ls ~/Applications 2>/dev/null"
  fi
  t "grep -n -i -E 'godspeed|hermes|local/bin' ~/.bashrc ~/.zshrc ~/.zprofile ~/.profile ~/.bash_profile 2>/dev/null"
}

section "before uninstalling: what is there"
leftovers

section "Stop the notebook"
if [ "$PLATFORM" = linux ]; then
  t "systemctl status godspeed-integrated-notebook.service --no-pager"
  t "sudo systemctl disable --now godspeed-integrated-notebook.service"
  t "sudo rm /etc/systemd/system/godspeed-integrated-notebook.service"
  t "sudo systemctl daemon-reload"
  t "systemctl --user status godspeed-integrated-notebook.service --no-pager"
else
  # On a Mac the guide says: close the terminal window where the notebook runs. The workflow
  # started it in the background; this is that window closing.
  t "pkill -f 'integrated-runtime/start.mjs' ; sleep 3; pkill -f supervise.mjs; sleep 2; curl -s -m 5 http://127.0.0.1:47831/health || echo stopped"
fi

section "Remove the timed jobs (crontab -e is interactive; the same edit, done without an editor)"
t "crontab -l"
t "crontab -l | grep -v -e prompt-harvest -e mc-notebook-sync | crontab -; crontab -l"

section "Remove the browser helper (only if it was lent; it was not)"
if [ "$PLATFORM" = linux ]; then
  t "ls -la ~/.config/autostart/godspeed-computer.desktop ~/.local/bin/godspeed-browser ~/.local/share/godspeed/computer"
else
  t "ls -la ~/Library/LaunchAgents/com.godspeedmissioncontrol.computer.plist ~/Library/Application\\ Support/Godspeed/computer ~/Applications/Godspeed\\ Mission\\ Control"
fi

section "Remove the commands and settings"
t "ls ~/.local/bin/mc-* ; rm -f ~/.local/bin/mc-*"
t "rm -rf ~/.godspeed"
t "ls -la ~/.local/bin/hermes; rm -f ~/.local/bin/hermes; rm -rf ~/.hermes"

section "Remove your mission control folder"
t "rm -rf ~/godspeed-v2"

section "after the guide's steps: what is still on this computer"
leftovers
t "ls -la ~/.local/bin ~/.local/share 2>/dev/null"
t "command -v hermes mc-due node gh git"
echo
echo "unix-uninstall done"
