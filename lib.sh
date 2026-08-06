# shellcheck shell=bash
# =============================================================================
# kit-bootstrap / lib.sh
#
# The parts every one of our installers was copying by hand. This file is the
# single place they live now.
#
# Consumers use it one of two ways, and both read THIS file as the source:
#
#   Runtime fetch (free installers - the book kit, found.sh):
#     eval "$(curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v1/lib.sh)"
#
#   Vendored at build time (paid kits - Hermes, OpenClaw, Paperclip):
#     build.sh pins a tag and copies this file into the tarball, so the buyer
#     still gets one self-contained offline artifact.
#
# Rules for editing this file:
#   - It is sourced/eval'd into someone else's shell. It must never `exit` at
#     load time, never `set -e`, and never leave stray output on load.
#   - Every function is prefixed `kb_` OR is one of the six short names the
#     existing installers already use (log/warn/die/ok/say/sudo_cmd), so a kit
#     can drop its local copy and change nothing else.
#   - Breaking changes go to a v2 branch. The v1 branch only gets fixes.
# =============================================================================

KB_LIB_VERSION="1.0.0"

# --- Output ------------------------------------------------------------------
# The same colour-printf block that was pasted into all four installers. The
# tag is settable so each installer keeps its own voice ([install], [found]...).
KB_TAG="${KB_TAG:-install}"

log()  { printf "\033[1;34m[%s]\033[0m %s\n" "$KB_TAG" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m[stop]\033[0m %s\n" "$*" >&2; exit 1; }
ok()   { printf "   ok: %s\n" "$*"; }
say()  { printf '\n== %s\n' "$*"; }

# --- Privilege ---------------------------------------------------------------
# Run a command as root whether we ARE root or have to reach for sudo. A box
# with neither is a clear message, not a confusing permission error 40 lines on.
sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    if ! command -v sudo >/dev/null 2>&1; then
      die "This needs root, and there is no sudo on this machine. Log in as root and run it again."
    fi
    sudo "$@"
  fi
}

kb_is_root() { [ "$(id -u)" -eq 0 ]; }

# --- Prerequisites -----------------------------------------------------------
# need_tools git curl xz
#
# Installs only what is actually missing, and runs `apt-get update` at most once
# no matter how many tools are missing. The name you type is the COMMAND name;
# the apt package is looked up, because the two differ often enough to have
# burned us before (xz lives in xz-utils, and a script that apt-installs "xz"
# fails with a message that names the wrong thing).
kb_apt_package_for() {
  case "$1" in
    xz)         echo "xz-utils" ;;
    sha256sum)  echo "coreutils" ;;
    file)       echo "file" ;;
    *)          echo "$1" ;;
  esac
}

KB_APT_UPDATED=0
need_tools() {
  local missing="" t pkg
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
  done
  [ -n "$missing" ] || return 0

  if ! command -v apt-get >/dev/null 2>&1; then
    die "This machine is missing:$missing
   I can only install these automatically on Ubuntu or Debian. Install them
   yourself, then run this again."
  fi

  for t in $missing; do
    if [ "$KB_APT_UPDATED" -eq 0 ]; then
      log "Refreshing the list of available software..."
      sudo_cmd apt-get update -y >/dev/null 2>&1 || warn "Could not refresh the software list; trying the install anyway."
      KB_APT_UPDATED=1
    fi
    pkg="$(kb_apt_package_for "$t")"
    log "Installing $t..."
    sudo_cmd apt-get install -y "$pkg" >/dev/null \
      || die "Could not install $t (package $pkg). Install it by hand and run this again."
  done
}

# --- Claude Code -------------------------------------------------------------
# Adopt an existing install, else fetch one. Sets KB_CLAUDE_BIN.
#
# The pre-export of PATH before running Anthropic's installer is deliberate:
# without it, that installer ends by warning that ~/.local/bin is not on PATH,
# which we then make untrue two lines later. The warning is a false alarm and it
# scares people mid-install.
ensure_claude_code() {
  # Anthropic's installer refuses to run under `sudo` from a normal user's
  # shell, and it is right to: it installs into $HOME, which under sudo is
  # root's home, so the binary lands somewhere the person's own shell cannot
  # see it. Plain root with no sudo is fine and explicitly allowed. Catch the
  # bad case here, where we can say something useful, instead of letting the
  # reader meet a refusal from a script they did not know they were running.
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    die "This is running under sudo, and Claude Code installs into your home folder.
   Under sudo that would be root's home, and the 'claude' command would then not
   work from your own account. Run the same command again WITHOUT sudo."
  fi

  if ! command -v claude >/dev/null 2>&1; then
    if [ -x "$HOME/.local/bin/claude" ]; then
      log "Claude Code is already on this machine. Making it reachable."
      export PATH="$HOME/.local/bin:$PATH"
      kb_persist_path
    else
      log "Installing Claude Code..."
      export PATH="$HOME/.local/bin:$PATH"
      curl -fsSL https://claude.ai/install.sh | bash \
        || die "The Claude Code installer did not finish. Read what it printed above."
      kb_persist_path
    fi
  else
    log "Claude Code is already here. Reusing it."
  fi

  KB_CLAUDE_BIN="$HOME/.local/bin/claude"
  command -v "$KB_CLAUDE_BIN" >/dev/null 2>&1 || KB_CLAUDE_BIN="$(command -v claude || echo claude)"
  export KB_CLAUDE_BIN

  local ver
  ver="$("$KB_CLAUDE_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  log "Claude Code version: ${ver:-unknown}"
}

kb_persist_path() {
  grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null && return 0
  # shellcheck disable=SC2016  # the literal string is what belongs in .bashrc
  printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc"
}

# --- GitHub CLI --------------------------------------------------------------
# Why this is here at all: it is what lets a reader authenticate with a one-time
# code on their phone instead of creating a personal access token by hand. It
# also replaces the ssh-keygen + deploy-key dance, because gh sets up git's
# credentials as part of signing in.
#
# The apt block below is copied from GitHub's own install_linux.md (verified
# 2026-08-06), with `sudo` swapped for sudo_cmd so it also works as root, where
# there is often no sudo binary at all.
ensure_gh() {
  if command -v gh >/dev/null 2>&1; then
    log "GitHub CLI is already here. Reusing it."
    return 0
  fi

  log "Installing the GitHub CLI..."
  need_tools wget

  local keyring="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
  local tmp; tmp="$(mktemp)"

  sudo_cmd mkdir -p -m 755 /etc/apt/keyrings
  wget -nv -O "$tmp" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    || die "Could not download GitHub's signing key. Check the machine has internet."
  sudo_cmd tee "$keyring" < "$tmp" >/dev/null
  rm -f "$tmp"
  sudo_cmd chmod go+r "$keyring"
  sudo_cmd mkdir -p -m 755 /etc/apt/sources.list.d
  printf 'deb [arch=%s signed-by=%s] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" "$keyring" \
    | sudo_cmd tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo_cmd apt-get update -y >/dev/null 2>&1
  sudo_cmd apt-get install -y gh >/dev/null \
    || die "Could not install the GitHub CLI. Run 'sudo apt install gh' by hand and read what it says."

  command -v gh >/dev/null 2>&1 || die "The GitHub CLI installed but is not on PATH."
  log "GitHub CLI $(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
}

# --- Asking the person in front of us ----------------------------------------
# There are two different ways to reach a human, and an installer like this hits
# both in a single run:
#
#   1. Started as `curl … | bash`: our stdin is the pipe carrying the script, so
#      reading from it would eat the rest of the script. We must open /dev/tty.
#   2. After `su - ai`: /dev/tty is owned by the login that opened it (root), so
#      the new user CANNOT open it. But the file descriptors handed over by the
#      exec still point at the terminal and still work.
#
# Checking only for (1) is what a plain `: < /dev/tty` test does, and it reports
# "no terminal" for every run that has switched user - which is every real run of
# this installer. Found on a live Ubuntu 24.04 box, where the install stopped at
# the sign-in with a terminal sitting right there. So resolve which channel we
# have, once, and use that everywhere.
# These two are separate functions so the decision below can be tested without a
# real terminal, which is the only reason the bug survived to a live box.
kb_stdin_is_tty()   { [ -t 0 ]; }
kb_can_open_tty()   { { : < /dev/tty; } >/dev/null 2>&1; }

KB_TTY=""
kb_resolve_tty() {
  [ -n "$KB_TTY" ] && return 0
  # Order matters. Ask "do I already have one?" BEFORE "can I open one?",
  # because after su the answer to the second is no and the first is yes.
  if kb_stdin_is_tty; then KB_TTY="inherited"
  elif kb_can_open_tty; then KB_TTY="device"
  else KB_TTY="none"; fi
}
have_tty() { kb_resolve_tty; [ "$KB_TTY" != "none" ]; }

# Say something to the human, whichever channel we have.
kb_tell() {
  kb_resolve_tty
  case "$KB_TTY" in
    inherited) printf '%s\n' "$*" >&2 ;;
    device)    printf '%s\n' "$*" > /dev/tty ;;
  esac
}

# Read one line from the human into the named variable.
kb_read() {
  kb_resolve_tty
  case "$KB_TTY" in
    inherited) IFS= read -r "$1" || true ;;
    device)    IFS= read -r "$1" < /dev/tty || true ;;
    *)         eval "$1=''" ;;
  esac
}

# Run an interactive command (a sign-in that prints a code and waits) on
# whichever channel reaches the human.
kb_run_interactive() {
  kb_resolve_tty
  case "$KB_TTY" in
    inherited) "$@" ;;
    device)    "$@" < /dev/tty > /dev/tty 2>&1 ;;
    *)         return 1 ;;
  esac
}

# --- The two sign-ins, which MUST happen here and not later ------------------
# Both of these print a code and wait for a human to come back. That only works
# while this script still owns the terminal. Once we hand over to Claude Code,
# every command runs to completion before Claude sees any output, so anything
# that waits on a person waits forever. This is the single most expensive
# ordering mistake available in an installer like this, so both sign-ins are
# done here, up front, on the real terminal.

# Signs Claude Code in to the reader's own Anthropic account.
#
# `auth login`, NOT `setup-token`. This was the other way round until a live run
# on Ubuntu 24.04 showed what `setup-token` actually does: it mints a long-lived
# token, PRINTS IT TO THE SCREEN, and stores nothing. Afterwards `auth status`
# still reports loggedIn:false and there is no credentials file. So it never
# signed the machine in, and it put a year-long credential into the terminal
# scrollback of a machine the reader just rented. `auth login` does the same
# no-browser code dance and persists the result, showing nothing.
ensure_claude_signin() {
  [ -n "${KB_CLAUDE_BIN:-}" ] || die "ensure_claude_signin called before ensure_claude_code."

  if "$KB_CLAUDE_BIN" auth status 2>/dev/null | grep -q '"loggedIn": *true'; then
    log "Claude Code is already signed in here."
    return 0
  fi

  have_tty || die "Claude Code is not signed in, and there is no terminal to sign in through.
   Run this installer directly on the machine instead of piping it through something."

  kb_tell "
  ---------------------------------------------------------------
  Claude Code needs to be signed in to your account.

  This machine has no web browser, so it cannot open the sign-in
  page itself. What happens instead:

    1. It prints a long web address below.
    2. You open that address on the computer or phone you are
       reading this on.
    3. You approve it there, and it gives you back a short code.
    4. You paste that code here.

  Read the approval screen before you accept it. It says the
  server's work is paid out of the subscription you already have.
  ---------------------------------------------------------------
"

  kb_run_interactive "$KB_CLAUDE_BIN" auth login --claudeai \
    || die "Sign-in did not finish. Run '$KB_CLAUDE_BIN auth login' by hand and read what it says."

  "$KB_CLAUDE_BIN" auth status 2>/dev/null | grep -q '"loggedIn": *true' \
    || die "Sign-in ran but Claude Code still reports it is not signed in.
   If you used 'setup-token' by hand, that is why: it prints a token and stores
   nothing. Run '$KB_CLAUDE_BIN auth login' instead."
  ok "Claude Code is signed in"
}

# Signs the GitHub CLI in with a one-time code, which is what replaces making a
# personal access token by hand AND the whole deploy-key dance: signing in this
# way also teaches git how to push, so nothing has to be pasted into a website.
ensure_gh_auth() {
  command -v gh >/dev/null 2>&1 || die "ensure_gh_auth called before ensure_gh."

  if gh auth status >/dev/null 2>&1; then
    log "GitHub is already signed in here as $(gh api user --jq .login 2>/dev/null || echo 'an existing account')."
    return 0
  fi

  have_tty || die "GitHub is not signed in, and there is no terminal to sign in through."

  kb_tell "
  ---------------------------------------------------------------
  Now the same thing for GitHub, which is where your folder is
  backed up.

  It will show you a short code and a web address. Open that
  address on your phone or laptop, type the code, and approve.

  You do not need to make a token, and you do not need to paste
  any key into a website. Signing in this way also sets up the
  permission this machine needs to push your files back.
  ---------------------------------------------------------------
"

  kb_run_interactive gh auth login --hostname github.com --git-protocol https --web --skip-ssh-key \
    || die "GitHub sign-in did not finish. Run 'gh auth login' by hand and read what it says."

  gh auth status >/dev/null 2>&1 || die "Sign-in ran but GitHub still reports this machine is not signed in."
  gh auth setup-git >/dev/null 2>&1 || warn "Signed in, but could not set git up to use it. 'gh auth setup-git' will fix that."
  ok "GitHub is signed in as $(gh api user --jq .login 2>/dev/null || echo 'you')"
}

# ask "Question" "default" -> answer on stdout
ask() {
  local prompt="$1" default="${2:-}" answer=""
  have_tty || { printf '%s' "$default"; return 0; }
  if [ -n "$default" ]; then
    kb_tell "$(printf "\033[1;34m[%s]\033[0m %s [%s]: " "$KB_TAG" "$prompt" "$default")"
  else
    kb_tell "$(printf "\033[1;34m[%s]\033[0m %s: " "$KB_TAG" "$prompt")"
  fi
  kb_read answer
  printf '%s' "${answer:-$default}"
}

# ask_yes "Question" "y" -> returns 0 for yes, 1 for no
ask_yes() {
  local answer; answer="$(ask "$1 (y/n)" "${2:-y}")"
  case "$answer" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# --- Becoming the right user -------------------------------------------------
# Our installers keep needing the same two-account dance: root is what you are
# handed when you rent a machine, and root is exactly what the assistant must
# not be. Paperclip's installer solved this alone; now everyone gets it.
#
# Needs KB_SELF_URL set by the caller, because a script running as `curl | bash`
# has no file on disk to re-run.
reexec_as_user() {
  local target="$1"
  kb_is_root || return 0

  [ -n "${KB_SELF_URL:-}" ] || die "reexec_as_user needs KB_SELF_URL set to this script's own address."

  if ! id -u "$target" >/dev/null 2>&1; then
    log "Making the account '$target', which is the one your assistant will live in."
    adduser --disabled-password --gecos "" "$target" >/dev/null \
      || die "Could not create the account '$target'."
  fi

  local carry="/home/$target/.kit-bootstrap-resume.sh"
  curl -fsSL "$KB_SELF_URL" -o "$carry" || die "Could not re-download this installer to hand it to '$target'."
  chown "$target":"$target" "$carry"
  chmod 0755 "$carry"

  log "Switching to the '$target' account. Everything from here runs without root."
  # Hand the terminal over. After this the new user cannot OPEN /dev/tty, because
  # it belongs to the login that opened it. These inherited descriptors keep
  # working, and kb_resolve_tty on the other side detects exactly that.
  kb_resolve_tty
  if [ "$KB_TTY" = "device" ]; then
    exec su - "$target" -c "KB_REEXEC=1 bash '$carry'" < /dev/tty
  else
    exec su - "$target" -c "KB_REEXEC=1 bash '$carry'"
  fi
}

# --- Handing over to Claude Code ---------------------------------------------
# Every installer ends the same way: bash has done the parts that are the same
# for everybody, and the rest is a conversation. This is that handover, plus the
# headless fallback each one used to hand-roll.
#
#   handoff "<the prompt>" [working directory]
handoff() {
  local prompt="$1" workdir="${2:-$PWD}"
  [ -n "${KB_CLAUDE_BIN:-}" ] || die "handoff called before ensure_claude_code."

  if have_tty; then
    log "Everything the machine can do on its own is done. Starting the setup conversation..."
    echo
    cd "$workdir" || die "No folder at $workdir."
    kb_resolve_tty
    if [ "$KB_TTY" = "device" ]; then
      exec "$KB_CLAUDE_BIN" "$prompt" < /dev/tty
    else
      exec "$KB_CLAUDE_BIN" "$prompt"
    fi
  fi

  cat <<EOF

===================================================================
The groundwork is installed, but there is no terminal here to talk
to you through (this looks like a piped or automated run).

To finish, run:

  cd $workdir && $KB_CLAUDE_BIN

Then paste this one line:

  $prompt
===================================================================
EOF
}
