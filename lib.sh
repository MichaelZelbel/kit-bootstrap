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
# `auth login`, not `setup-token`. Both work; they are different jobs.
#
# `setup-token` mints a long-lived token and PRINTS IT for you to store yourself,
# typically as CLAUDE_CODE_OAUTH_TOKEN. That is a perfectly good pattern and it
# is what the book's own server does, because brief.sh sources ~/.hub-env with
# `set -a` and so picks the variable up. It does not, on its own, sign the
# machine in: right after it runs, `auth status` still says loggedIn:false.
#
# This installer used `setup-token` first and then checked "is this machine
# signed in?", which is a question `setup-token` never claimed to answer. That
# check failed, correctly, because nothing had captured the printed token.
#
# `auth login` is the better fit HERE for two reasons that have nothing to do
# with the other command being wrong: nothing has to be scraped out of an
# interactive program's output, and no secret is ever put on screen. Verified on
# Ubuntu 24.04 that the credential it writes works for a completely clean,
# non-interactive run - which is what cron does at three in the morning.
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
# A freshly installed Claude Code stops for THREE first-run questions before it
# will look at a prompt, and an installer that hands over without answering them
# strands the person in a wizard they were never told about:
#
#   1. a theme picker
#   2. "Claude account or Console account?" - asked even when auth login has
#      already succeeded, and answering it starts a SECOND sign-in
#   3. "Do you trust this folder?", asked per directory
#
# All three are settings, so answer them here. Signing in and then being asked to
# sign in again is the one that really hurts: on a live run it sent the reader
# back to a fresh OAuth URL seconds after they had finished the first one.
#
# On (3): pre-accepting the trust prompt is right in this context and only this
# one. The folder is the person's own repository, which they just named, and this
# installer is what put it there and what is starting Claude in it.
kb_skip_claude_first_run() {
  local workdir="$1" cfg="$HOME/.claude.json" ver tmp
  command -v jq >/dev/null 2>&1 || return 0
  ver="$("$KB_CLAUDE_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  [ -f "$cfg" ] || echo '{}' > "$cfg"
  tmp="$(mktemp)"
  jq --arg v "$ver" --arg d "$workdir" '
      .hasCompletedOnboarding    = true
    | .lastOnboardingVersion     = $v
    | .theme                     = (.theme // "dark")
    | .fullscreenUpsellSeenCount = ((.fullscreenUpsellSeenCount // 0) + 9)
    | .projects                  = ((.projects // {}) * { ($d): (((.projects // {})[$d] // {})
        + { hasTrustDialogAccepted: true, projectOnboardingSeenCount: 1 }) })
  ' "$cfg" > "$tmp" 2>/dev/null && mv "$tmp" "$cfg" || {
    rm -f "$tmp"
    # Soft failure on purpose: a wizard the reader has to click through is a far
    # better outcome than a broken install. But say so, because otherwise the
    # three questions arrive with no explanation of where they came from.
    warn "Could not pre-answer Claude Code's first-run questions. It may ask you
   about a colour theme, which account to use, and whether you trust this folder.
   Answer them and it will carry on."
  }
}

# Give the assistant permission to work, in advance.
#
# Chapter 25 of the book teaches exactly this and it applies to the installer
# itself: on a laptop the leash is a question, and on a server there is nobody
# awake to answer it, so a question is a refusal. Without this the reader is
# asked to approve every single file read, one at a time, during their own
# install. Safety comes from the account being able to reach almost nothing.
#
# Never clobbers an existing settings.json - it is backed up first, the way the
# Hermes kit does it, because a machine may already be somebody's working setup.
#
# WRITE ONLY KEYS THAT ARE IN THE SCHEMA. This file is Claude Code's own, and it
# rewrites it. A profile carrying an explanatory "_comment" array and a custom
# marker key was silently replaced with a two-line file of Claude Code's own
# settings the moment it started, which took the permissions with it and put the
# reader back to approving every file read one at a time. Verified on Ubuntu
# 24.04: identical profile minus those two keys survives untouched. So the
# explanation lives in settings/README.md, and "is this ours?" is answered by
# comparing the file with the source rather than by tagging it.
kb_grant_working_permissions() {
  local src="$1" dest="$HOME/.claude/settings.json" tmp d
  [ -f "$src" ] || { warn "No permission profile at $src; Claude Code will ask before every step."; return 0; }
  mkdir -p "$HOME/.claude"

  # Folders outside the one Claude is started in go in the settings, not on the
  # command line. `--add-dir` takes a variable number of values, so a trailing
  # prompt argument is swallowed as one more directory and never runs: on a live
  # box Claude Code opened at an empty prompt and just sat there.
  if [ -n "${KB_EXTRA_DIRS:-}" ] && command -v jq >/dev/null 2>&1; then
    local dirs="[]"
    for d in ${KB_EXTRA_DIRS}; do
      [ -d "$d" ] && dirs="$(printf '%s' "$dirs" | jq --arg d "$d" '. + [$d]')"
    done
    tmp="$(mktemp)"
    jq --argjson dirs "$dirs" '.permissions.additionalDirectories = $dirs' "$src" > "$tmp" 2>/dev/null \
      && src="$tmp"
  fi

  if [ -f "$dest" ] && ! cmp -s "$dest" "$src"; then
    cp "$dest" "$dest.before-install"
    log "Kept your existing Claude settings as settings.json.before-install"
  fi
  cp "$src" "$dest"
  [ -n "${tmp:-}" ] && rm -f "$tmp"
  return 0
}

# handoff "<the prompt>" [working directory]
#
# Set KB_EXTRA_DIRS to a space-separated list of folders outside the working
# directory that the assistant must be able to read. The permission profile's
# Read(**) is scoped to the project folder, so an installer whose instructions
# live somewhere else (the kit, the shared step sheets) still gets a permission
# prompt for every one of them - which on a server is the same as a refusal.
handoff() {
  local prompt="$1" workdir="${2:-$PWD}"
  [ -n "${KB_CLAUDE_BIN:-}" ] || die "handoff called before ensure_claude_code."
  kb_skip_claude_first_run "$workdir"
  [ -n "${KB_PERMISSION_PROFILE:-}" ] && kb_grant_working_permissions "$KB_PERMISSION_PROFILE"

  # Extra folders are handled in the settings file above, deliberately NOT with
  # --add-dir. See kb_grant_working_permissions for why.

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

# --- Joining a machine to a hub that already exists ---------------------------
#
# Every installer here answers "make me a hub from nothing". None of them
# answered "I already have a hub, this is a second machine", so that job was
# written separately in Michael's own repo and had to be written AGAIN for
# readers. That is the drift this repo exists to stop, so it lives here now and
# both callers use it.
#
# What it fixes, concretely: an AI assistant keeps its memory of you in a folder
# belonging to the TOOL, not to your hub. So the memory never leaves that one
# machine and no other assistant can read it. Linking that folder into the hub
# makes one memory that every machine and every assistant shares, carried by the
# same git sync that already carries everything else.

# kb_ai_memory_path <hub-dir>
# Where Claude Code keeps the memory for that hub folder. Derived, never typed:
# it mangles the absolute path the same way Claude Code does, so this keeps
# working when the hub sits somewhere else on the next machine.
kb_ai_memory_path() {
  local hub="$1" mangled
  mangled="$(printf '%s' "$hub" | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')"
  printf '%s' "$HOME/.claude/projects/$mangled/memory"
}

# kb_seed_memory_index <hub-dir>
# A memory folder with nothing in it is a mystery. One index file with one line
# explaining itself is the difference between a feature and a stray directory.
kb_seed_memory_index() {
  local hub="$1" idx="$1/memory/MEMORY.md"
  mkdir -p "$hub/memory"
  [ -f "$idx" ] && return 0
  cat > "$idx" <<'IDX'
# Memory index

This is what your assistants have learned about you and your work, one file per
fact, and this page is the list of them. Your assistant reads this list at the
start of a session and opens only the files it needs, so the list stays small
and the facts stay out of the way until they matter.

It lives in your hub folder rather than inside one AI tool, so every assistant
on every one of your machines reads the same memory.

One line per memory, like this:

- [What it is](some-fact.md) - the short version, so a session can tell whether to open it
IDX
  ok "memory: created the index at $hub/memory/MEMORY.md"
}

# kb_link_ai_memory <hub-dir>
# Point the assistant's private memory folder at the hub's memory/ folder.
# Safe to run again: it never deletes a memory, and it repairs a link that points
# somewhere else (an older hub path) instead of reporting it as fine.
kb_link_ai_memory() {
  local hub="$1" mem link stash f
  [ -n "$hub" ] || { warn "kb_link_ai_memory needs the hub folder"; return 1; }
  # The index belongs to the hub, not to any one tool, so it is seeded even when
  # the link below is skipped.
  kb_seed_memory_index "$hub"
  # Only for a machine that actually has Claude Code, and whose owner has not
  # switched it off. Before this guard, a machine that had never seen Claude
  # Code got a fabricated ~/.claude profile folder out of nowhere. The two
  # functions it leans on live a little further down this file.
  if ! kb_ai_tool_detected claude; then
    ok "memory: Claude Code is not on this machine, so there is no memory folder to share yet. Run this again once it is installed."
    return 0
  fi
  case ",$(kb_enabled_sources)," in
    *,claude,*) ;;
    *) ok "memory: you chose not to sync Claude Code on this machine, so its memory folder was left alone."
       return 0 ;;
  esac
  mem="$hub/memory"
  link="$(kb_ai_memory_path "$hub")"

  if [ -L "$link" ]; then
    # A link that points at the WRONG hub is the failure that looks like success:
    # the assistant writes memories into a folder nobody syncs any more.
    local target
    target="$(readlink "$link")"
    if [ "$target" = "$mem" ] || [ "$(cd "$link" 2>/dev/null && pwd -P)" = "$(cd "$mem" 2>/dev/null && pwd -P)" ]; then
      ok "memory: already shared with $mem"
      return 0
    fi
    warn "memory: the link pointed at $target, not at this hub. Repointing it."
    rm -f "$link"
  elif [ -d "$link" ]; then
    # Real memories from before this ran. Carry them in, then move the folder
    # aside with a timestamp. Never delete: a memory nobody can get back is the
    # one thing this whole design exists to prevent.
    for f in "$link"/*; do
      [ -f "$f" ] || continue
      [ -e "$mem/$(basename "$f")" ] || { cp "$f" "$mem/"; ok "memory: carried over $(basename "$f")"; }
    done
    stash="$link.replaced-$(date +%Y%m%d%H%M%S)"
    mv "$link" "$stash"
    ok "memory: your old folder is kept at $stash (delete it once you are happy)"
  fi

  mkdir -p "$(dirname "$link")"
  ln -sfn "$mem" "$link"
  ok "memory: $link now points at $mem, so every machine shares it"
}

# =============================================================================
# WHICH AI TOOLS LIVE ON THIS MACHINE, AND WHICH OF THEM MAY BE SYNCED
#
# Added 2026-08-11. Before this, the installer wired sync with no detection, no
# disclosure and no choice: it created a Claude Code memory link on machines
# that had never seen Claude Code, and the harvest read Codex's conversation
# logs and pushed them to the hub's repository without one sentence saying so.
# Both are the same fault: doing something to a person's data without looking
# first or telling them.
#
# Three ideas, kept separate on purpose:
#   DETECTED  the tool leaves files on this machine, so we can see it is here.
#   SYNCABLE  this kit knows how to read what the person typed to it. Today that
#             is Claude Code (memory + prompts), Codex (prompts) and Hermes chat
#             bots (prompts). Everything else is shown with the reason it is not.
#   ENABLED   the person said yes. Recorded per device in ~/.hub/device.env as
#             HUB_PROMPT_SOURCES, because "my work laptop's Codex must stay out"
#             is a fact about one machine, not about the hub.
#
# A tool that is detected but not syncable is NAMED with its reason, never
# silently promised: "every assistant shares one memory" was written on every
# completion screen while exactly one assistant was wired, and that ends here.
# =============================================================================

# The sources the harvester can actually read. One list, referenced everywhere,
# so adding a source is one edit here plus a reader in the collector.
KB_SUPPORTED_SOURCES="claude codex hermes"

# kb_ai_tool_detected <id>
# Does this AI tool leave files on this machine? Fingerprints verified on real
# installs (2026-08-11); a wrong guess here can only fail to see a tool, never
# invent one, because everything is a plain "does this folder exist".
#
# KB_ASSUME_TOOLS is the test override: a comma list of ids to report as
# present, or "-" for a machine with nothing. Detection reads the machine it
# runs on, so without this a test wanting "a PC with no Claude Code" would have
# to hide the real one.
kb_ai_tool_detected() {
  if [ -n "${KB_ASSUME_TOOLS:-}" ]; then
    case ",$KB_ASSUME_TOOLS," in *",$1,"*) return 0 ;; *) return 1 ;; esac
  fi
  case "$1" in
    claude)         [ -d "$HOME/.claude" ] || command -v claude >/dev/null 2>&1 ;;
    codex)          [ -d "$HOME/.codex" ] ;;
    hermes)         [ -d "$HOME/.hermes/profiles" ] || [ -d /home/hermes/.hermes/profiles ] ;;
    claude-desktop) [ -d "$HOME/Library/Application Support/Claude" ] || \
                    [ -d "${APPDATA:-/nonexistent}/Claude" ] || \
                    [ -d "${LOCALAPPDATA:-/nonexistent}/AnthropicClaude" ] ;;
    muse)           [ -d "$HOME/.config/muse" ] || [ -d "$HOME/.local/share/muse" ] || \
                    command -v muse >/dev/null 2>&1 ;;
    opencode)       [ -d "$HOME/.config/opencode" ] || command -v opencode >/dev/null 2>&1 ;;
    openclaw)       [ -d "$HOME/.openclaw" ] ;;
    comet)          [ -d "$HOME/Library/Application Support/Perplexity/Comet" ] || \
                    [ -d "${LOCALAPPDATA:-/nonexistent}/Perplexity/Comet" ] ;;
    copilot)        [ -d "$HOME/.copilot" ] ;;
    cursor)         [ -d "$HOME/.cursor" ] || [ -d "${APPDATA:-/nonexistent}/Cursor" ] ;;
    gemini)         [ -d "$HOME/.gemini" ] ;;
    *) return 1 ;;
  esac
}

# kb_ai_tool_info <id>   ->   sync|Human name|why not, when sync is none
# "sync" is what this kit can read TODAY, not what the tool could offer.
kb_ai_tool_info() {
  case "$1" in
    claude)         printf 'memory+prompts|Claude Code|' ;;
    codex)          printf 'prompts|Codex|' ;;
    hermes)         printf 'prompts|Hermes chat bots|' ;;
    claude-desktop) printf 'none|Claude Desktop|keeps your conversations on its own servers, not in files here' ;;
    comet)          printf 'none|Perplexity Comet|keeps your conversations on its own servers, not in files here' ;;
    muse)           printf 'none|Muse Code|keeps files here, but this kit cannot read its format yet' ;;
    opencode)       printf 'none|OpenCode|keeps files here, but this kit cannot read its format yet' ;;
    openclaw)       printf 'none|OpenClaw|keeps files here, but this kit cannot read its format yet' ;;
    copilot)        printf 'none|GitHub Copilot|keeps files here, but this kit cannot read its format yet' ;;
    cursor)         printf 'none|Cursor|keeps files here, but this kit cannot read its format yet' ;;
    gemini)         printf 'none|Gemini CLI|keeps files here, but this kit cannot read its format yet' ;;
    *) return 1 ;;
  esac
}

# kb_detect_ai_tools
# One line per AI tool found on this machine:  id|sync|Human name|note
# Order is fixed and syncable-first, so every caller (the report below, the
# Windows wizard's checklist) shows the same list in the same order.
kb_detect_ai_tools() {
  local id
  for id in claude codex hermes claude-desktop muse opencode openclaw comet copilot cursor gemini; do
    kb_ai_tool_detected "$id" && printf '%s|%s\n' "$id" "$(kb_ai_tool_info "$id")"
  done
  return 0
}

# kb_enabled_sources
# Which syncable tools the person has said yes to, as a comma list. Who decides,
# in order: a --sources flag this run (KB_SYNC_SOURCES, where empty means NONE,
# because unticking every box is a decision and not an accident), the choice
# recorded on this device, and only then "every syncable tool found here", which
# is what every machine did before there was a choice.
kb_enabled_sources() {
  # "-" is NONE spelled so it survives a Windows environment variable, which
  # cannot hold an empty string. Both spellings are accepted everywhere.
  local v id list=""
  if [ -n "${KB_SYNC_SOURCES+x}" ]; then
    v="$KB_SYNC_SOURCES"
    [ "$v" = "-" ] && v=""
    printf '%s' "$v"; return 0
  fi
  if [ -f "$HOME/.hub/device.env" ]; then
    v="$(sed -n 's/^[[:space:]]*HUB_PROMPT_SOURCES=//p' "$HOME/.hub/device.env" 2>/dev/null | tail -1)"
    if grep -q '^[[:space:]]*HUB_PROMPT_SOURCES=' "$HOME/.hub/device.env" 2>/dev/null; then
      [ "$v" = "-" ] && v=""
      printf '%s' "$v"; return 0
    fi
  fi
  for id in $KB_SUPPORTED_SOURCES; do
    kb_ai_tool_detected "$id" && list="$list,$id"
  done
  printf '%s' "${list#,}"
}

# kb_write_prompt_sources <comma-list>
# Record the choice on this device. In device.env rather than the hub, because
# the hub travels to every machine and this is a fact about one of them.
kb_write_prompt_sources() {
  local v="$1" f="$HOME/.hub/device.env" tmp
  mkdir -p "$HOME/.hub"
  if [ -f "$f" ] && grep -q '^[[:space:]]*HUB_PROMPT_SOURCES=' "$f" 2>/dev/null; then
    tmp="$f.tmp.$$"
    sed "s|^[[:space:]]*HUB_PROMPT_SOURCES=.*|HUB_PROMPT_SOURCES=$v|" "$f" > "$tmp" && mv "$tmp" "$f"
  else
    printf 'HUB_PROMPT_SOURCES=%s\n' "$v" >> "$f"
  fi
  ok "recorded your choice on this device: HUB_PROMPT_SOURCES=$v (in $f)"
}

# kb_sync_report
# The truth about this machine, built from what was detected and chosen, never
# from the promise. This is what the completion screen prints, so a person who
# runs no other command still learns exactly what is read and where it goes.
kb_sync_report() {
  local on=",$(kb_enabled_sources)," line id sync name note synced="" off="" unsyncable=""
  while IFS='|' read -r id sync name note; do
    [ -n "$id" ] || continue
    if [ "$sync" = "none" ]; then
      unsyncable="$unsyncable  - $name: $note\n"
    elif [ "${on#*,$id,}" != "$on" ]; then
      case "$sync" in
        memory+prompts) synced="$synced  - $name: its memory folder, plus what you type to it and its answers\n" ;;
        *)              synced="$synced  - $name: what you type to it, and its answers\n" ;;
      esac
    else
      off="$off  - $name (switched off by your choice; edit HUB_PROMPT_SOURCES in ~/.hub/device.env to change it)\n"
    fi
  done <<EOF
$(kb_detect_ai_tools)
EOF
  if [ -n "$synced" ]; then
    printf 'What is synced from this machine into your hub, and pushed to its repository:\n'
    printf '%b' "$synced"
  else
    printf 'Nothing is synced from this machine: no AI tool here is both readable by this kit and switched on.\n'
  fi
  [ -n "$off" ] && { printf 'Found here but left alone:\n'; printf '%b' "$off"; }
  [ -n "$unsyncable" ] && { printf 'Found here but not syncable:\n'; printf '%b' "$unsyncable"; }
  return 0
}

# =============================================================================
# FINDING A HUB THAT ALREADY EXISTS, AND PUTTING ITS TOOLS WITHIN REACH
#
# Written 2026-08-09, after `hub map` on the Windows work PC answered with a file
# path from the rented server. Two separate holes had to be filled, and only the
# first one was obvious:
#
#   1. The tool did not know which copy of the hub it was reading. Fixed in the
#      tool itself.
#   2. There was no `hub` command on that machine at all. The rented server gets
#      one because its deploy script copies the tools into /usr/local/bin; no
#      other machine ran anything that did the same. So the fix in (1) would have
#      changed nothing for someone sitting at a laptop typing `hub map`.
#
# Hole 2 is install work, so per D-092 it lives here and nowhere else.
# =============================================================================

# kb_hub_looks_real <dir>
# Is this folder a hub, or just a folder called hub? Checked before every answer
# so discovery cannot hand back an empty directory that happens to match a name.
kb_hub_looks_real() {
  local d="${1:-}"
  [ -n "$d" ] && [ -d "$d/.git" ] || return 1
  [ -d "$d/memory" ] || [ -f "$d/AGENTS.md" ] || [ -f "$d/CLAUDE.md" ]
}

# kb_find_hub [hint]
# Print the hub already installed on this machine, or nothing. This is what makes
# "run the installer again on my other laptop" work without typing a path: the
# machine already knows where its hub is, in more than one way, so ask it.
kb_find_hub() {
  local c d
  for c in "${1:-}" "${HUB_DIR:-}" "${HUB:-}"; do
    [ -n "$c" ] || continue
    kb_hub_looks_real "$c" && { (cd "$c" && pwd -P); return 0; }
  done
  # A machine joined once before already told us: the assistant's memory folder is
  # a link straight into the hub. Walking INTO the link and asking where we landed
  # beats reading the folder's mangled name, which cannot be turned back into a
  # path (every one of : \ . and a space became the same dash).
  for c in "$HOME"/.claude/projects/*/memory; do
    [ -d "$c" ] || continue
    d="$(cd "$c" 2>/dev/null && pwd -P)" || continue
    d="$(dirname "$d")"
    kb_hub_looks_real "$d" && { printf '%s' "$d"; return 0; }
  done
  # The usual homes, last. /c/hub is how Git Bash on Windows spells C:\hub.
  for c in "$HOME/hub" /root/hub /c/hub "$HOME/Documents/hub" "$HOME/dev/hub"; do
    kb_hub_looks_real "$c" && { (cd "$c" && pwd -P); return 0; }
  done
  return 1
}

# kb_update_hub <hub-dir>
# Bring an existing installation up to date. Never fatal: a machine with no network
# should still finish wiring itself, it should just say plainly that it is behind.
kb_update_hub() {
  local hub="${1:-}" br
  [ -n "$hub" ] || { warn "kb_update_hub needs the hub folder"; return 1; }
  if [ ! -d "$hub/.git" ]; then
    warn "$hub is not a git folder, so there is nothing to pull. Continuing."
    return 0
  fi
  # A hub made on this machine five minutes ago has no remote yet, and telling its
  # owner it "could not pull" and "may be out of date" is alarming and untrue:
  # there is nowhere to be out of date FROM. Say the useful thing instead, which is
  # the one step that would make their folder reach their other machines.
  if ! git -C "$hub" remote get-url origin >/dev/null 2>&1; then
    ok "this hub lives only on this computer for now. Give it a home on GitHub when you are ready, and it will travel to your other machines."
    return 0
  fi
  br="$(git -C "$hub" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$br" ] && [ "$br" != "HEAD" ] || br=main
  if git -C "$hub" pull --rebase --autostash -q origin "$br" 2>/dev/null; then
    ok "updated your hub to $(git -C "$hub" log -1 --format='%h %s' 2>/dev/null)"
  else
    warn "could not pull (no network, or a conflict to sort out by hand).
     Continuing with the copy already on this machine, which may be out of date."
  fi
}

# kb_install_hub_cli <hub-dir>
# Put the hub's own command-line tools on this machine's PATH.
#
# ALL of them, not just `hub`. `hub memory search` is a one-line wrapper that runs
# `hub-memory-lookup` by bare name, so a PATH holding only `hub` gives you a command
# that exists and then fails — the worst of the three possible states. Nothing to do
# on a hub that ships no tools, which is every reader's hub, so this stays quiet there.
kb_install_hub_cli() {
  local hub="${1:-}" src bindir n
  src="$hub/agents/hub-cli"
  [ -d "$src" ] || return 0
  [ -f "$src/hub" ] || return 0
  bindir="$HOME/.local/bin"
  mkdir -p "$bindir"
  n=0
  for f in "$src"/hub "$src"/hub-*; do
    [ -f "$f" ] || continue
    case "$f" in *.env|*.md) continue ;; esac
    # Only when it is not already runnable. An unconditional chmod rewrites the file's mode
    # even when nothing needed changing, which shows up as 16 modified files in the hub's own
    # git folder every single time the installer runs. An installer that dirties the folder it
    # came to wire up looks exactly like an installer that changed something on purpose.
    [ -x "$f" ] || chmod +x "$f" 2>/dev/null || true
    ln -sfn "$f" "$bindir/$(basename "$f")" && n=$((n + 1))
  done
  kb_persist_path
  ok "commands: $n hub tools are now on your PATH from $bindir (open a new terminal for it to take)"
}

# kb_install_hub_tools <hub-dir> <tools-repo> [<tools-path>]
# Put the kit's own small programs on this computer.
#
# WHY THESE ARE NOT IN THE HUB FOLDER. The hub is a folder of text files and the book says so
# in Chapter 4: "Nothing here needs a terminal." A Node program and a Python program sitting in
# it would be the first two things in there that are not text files a person can read. So they
# are installed the way an assistant is installed, on the machine, and they write into the
# folder from outside. Same reasoning as kb_install_hub_cli one function up.
#
# WHY THEY ARE NOT COPIED INTO A PRIVATE FOLDER EITHER. Before 2026-08-10 the only copy of the
# prompt collector lived in one person's own hub, so the program the book promises its readers
# existed nowhere they could get it, and the author was running a version nobody else had. One
# copy, in the kit, installed identically on every machine, is the whole point of this function.
#
# Quiet on a kit that ships no `tools/` folder, which is every other product that uses this file.
kb_install_hub_tools() {
  local hub="${1:-}" repo="${2:-}" sub="${3:-tools}" tmp bindir f base n=0
  [ -n "$hub" ] || return 0
  [ -n "$repo" ] || return 0          # nothing to fetch from: not an error, just nothing to do

  tmp="$(mktemp -d 2>/dev/null)" || return 0
  if ! git clone --depth 1 --quiet "$repo" "$tmp" >/dev/null 2>&1; then
    rm -rf "$tmp"
    warn "prompt archive: I could not fetch the kit's programs from $repo, so the daily job has nothing to run yet. Check this computer can reach the internet and run this again."
    return 0
  fi
  if [ ! -d "$tmp/$sub" ]; then rm -rf "$tmp"; return 0; fi

  bindir="$HOME/.local/bin"
  mkdir -p "$bindir" "$HOME/.hub"
  for f in "$tmp/$sub"/*; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    case "$base" in *.md) continue ;; esac
    # REMOVE FIRST, ALWAYS. kb_install_hub_cli one function up puts SYMLINKS in this same
    # folder, pointing back into the hub. `cp` over a symlink writes through it, so a copy
    # here silently overwrote a file inside the hub itself the first time this ran live, and
    # the only sign was a git folder that had changed on its own. Deleting the name first
    # means we always write a file. The test for this can only run where symlinks are real,
    # so it says out loud when it is skipped.
    rm -f "$bindir/$base" 2>/dev/null
    cp "$f" "$bindir/$base" 2>/dev/null || continue
    chmod +x "$bindir/$base" 2>/dev/null || true
    n=$((n + 1))
  done
  rm -rf "$tmp"
  [ "$n" -gt 0 ] || return 0

  # The launcher. Not a symlink and not the .js file's own shebang: this way the program is
  # started by the node on PATH at the time it runs, and it finds its other half by sitting in
  # the same folder, which is the one thing a scheduled job can always be told.
  if [ -f "$bindir/prompt-harvest.js" ]; then
    printf '#!/bin/sh\nexec node "$(dirname "$0")/prompt-harvest.js" "$@"\n' > "$bindir/hub-prompt-harvest"
    chmod +x "$bindir/hub-prompt-harvest" 2>/dev/null || true
  fi

  # Where the hub is, recorded once, so a job started by the schedule with almost no
  # environment never has to guess. The programs read this file already.
  if [ ! -f "$HOME/.hub/device.env" ] || ! grep -q '^[[:space:]]*HUB_DIR=' "$HOME/.hub/device.env" 2>/dev/null; then
    printf 'HUB_DIR=%s\n' "$hub" >> "$HOME/.hub/device.env"
  fi

  kb_persist_path
  ok "prompt archive: installed the program that files what you type to an AI, and its answers ($bindir)"
}

# kb_install_prompt_harvest <hub-dir>
# Make this machine file what its owner types to an AI, by itself, every day.
#
# WHY THIS BELONGS IN THE INSTALLER. The hub keeps a drawer of everything he has typed to any
# assistant, so months later he can ask "how did I get that result in June" and be answered
# with the words he actually used. Filling that drawer needs something on each machine to run
# once a day, and until 2026-08-10 nothing installed it: the server had a line in its schedule
# because somebody typed one there by hand, and every other computer had nothing. A wiring
# step you perform by hand covers the machine you happened to be sitting at, which is the same
# lesson this kit already learned about the memory folder. So joining a machine wires this too.
#
# It is deliberately quiet on a hub that ships no harvester, which is every reader's hub for
# now: there is nothing to schedule, so there is nothing to say.
#
# KB_CRONTAB exists so the test suite can watch this work without editing the schedule of
# whoever is running the tests. A command name compiled into the code is a command no test
# can safely reach.
kb_install_prompt_harvest() {
  local hub="${1:-}" cron node cur line runner
  cron="${KB_CRONTAB:-crontab}"

  # The installed program first, the hub's own copy second. The second is only for a hub set up
  # before the programs were installed on the machine, so nothing breaks between the two.
  if [ -x "$HOME/.local/bin/hub-prompt-harvest" ]; then
    runner="$HOME/.local/bin/hub-prompt-harvest"
  elif [ -f "$hub/bin/prompt-harvest.js" ]; then
    runner=""
  else
    return 0
  fi

  node="$(command -v node 2>/dev/null || true)"
  if [ -z "$node" ]; then
    warn "prompt archive: Node.js is not on this computer, so what you type to an AI here (and its answers) cannot be filed. Install Node.js and run this again."
    return 0
  fi
  if ! command -v "$cron" >/dev/null 2>&1; then
    warn "prompt archive: this computer has no cron, so nothing can run the daily job. What you type here will only be filed when you run it yourself: node \"$hub/bin/prompt-harvest.js\""
    return 0
  fi

  cur="$("$cron" -l 2>/dev/null || true)"
  case "$cur" in
    *prompt-harvest*)
      ok "prompt archive: already scheduled on this computer"
      return 0 ;;
  esac

  # Hourly, not nightly, and the job itself does nothing if it already ran today. A fixed time
  # in the small hours is right for a server and wrong for a laptop, because the laptop is shut.
  mkdir -p "$HOME/.hub"
  if [ -n "$runner" ]; then
    line="17 * * * * \"$runner\" --once-a-day >> \"$HOME/.hub/prompt-harvest.log\" 2>&1"
  else
    line="17 * * * * \"$node\" \"$hub/bin/prompt-harvest.js\" --once-a-day >> \"$HOME/.hub/prompt-harvest.log\" 2>&1"
  fi
  if { [ -n "$cur" ] && printf '%s\n' "$cur"
       printf '%s\n%s\n' "# Keep the hub's record of what you type to an AI on this computer, and its answers, up to date." "$line"
     } | "$cron" - 2>/dev/null; then
    ok "prompt archive: this computer now files what you type to an AI, and its answers, once a day"
  else
    warn "prompt archive: I could not add the daily job to this computer's schedule. Run it by hand when you want it: ${runner:-node \"$hub/bin/prompt-harvest.js\"}"
  fi
}

# =============================================================================
# THE TWO HALVES A PERSON'S OWN COMPUTER NEEDED, AND ONLY WINDOWS HAD
#
# Added 2026-08-09 (D-105). That morning the Windows installer grew two abilities
# this file never got: fetching what the machine is missing, and MAKING a hub when
# there is none. So for a day, a reader on a Mac who ran the Mac command on a
# fresh machine got an error telling them to go and make a hub first, while a
# reader on Windows got a finished setup. Michael spotted the asymmetry from the
# outside and asked whether the .exe was the odd one out. It was not: the bash
# half was simply behind.
#
# Everything below is the bash twin of a function in join.ps1. When you change one,
# change the other, and add the case to BOTH test.sh and windows/test-windows.ps1.
# =============================================================================

# What kind of computer is this, in terms of how software gets installed here.
kb_os() {
  case "$(uname -s 2>/dev/null)" in
    Darwin) printf 'macos' ;;
    Linux)  if command -v apt-get >/dev/null 2>&1; then printf 'linux-apt'; else printf 'linux-other'; fi ;;
    *)      printf 'other' ;;
  esac
}

# Can we become root at all? Asked BEFORE reaching for sudo_cmd, because that one
# calls die, and a missing prerequisite must never kill a run that could still
# wire up everything else and tell the person what is left.
kb_can_sudo() { [ "$(id -u)" -eq 0 ] || command -v sudo >/dev/null 2>&1; }

# Anything that could not be installed, so the end of the run can name it.
KB_MISSING=""
kb_note_missing() { KB_MISSING="$KB_MISSING $1"; }

# kb_install_one <command> <apt-package> <brew-package> <human name>
# Returns 0 only when the command is genuinely reachable afterwards, because
# "the package manager exited 0" and "the tool works" are not the same claim.
kb_install_one() {
  local cmd="$1" aptpkg="$2" brewpkg="$3" human="$4"
  command -v "$cmd" >/dev/null 2>&1 && { ok "$human is already here"; return 0; }

  case "$(kb_os)" in
    linux-apt)
      if ! kb_can_sudo; then
        warn "$human is missing, and this account cannot install software (no root, no sudo).
   Ask whoever runs this machine to install $human, then run this again."
        kb_note_missing "$human"; return 1
      fi
      log "Installing $human..."
      if [ "${KB_APT_UPDATED:-0}" -eq 0 ]; then
        sudo_cmd apt-get update -y >/dev/null 2>&1 || warn "Could not refresh the software list; trying the install anyway."
        KB_APT_UPDATED=1
      fi
      sudo_cmd apt-get install -y "$aptpkg" >/dev/null 2>&1
      ;;
    macos)
      if ! command -v brew >/dev/null 2>&1; then
        # Homebrew is not installed for them here on purpose: it is a large change
        # to their machine and it asks for their password. Their decision, not ours.
        warn "$human is missing, and this Mac has no Homebrew, which is what fetches it.
   Install Homebrew first - it is one line from https://brew.sh - then run this again."
        kb_note_missing "$human"; return 1
      fi
      log "Installing $human..."
      brew install "$brewpkg" >/dev/null 2>&1
      ;;
    *)
      warn "$human is missing and I do not know how software is installed on this system.
   Install $human yourself, then run this again."
      kb_note_missing "$human"; return 1
      ;;
  esac

  if command -v "$cmd" >/dev/null 2>&1; then ok "$human installed"; return 0; fi
  warn "$human did not become usable after installing it. Open a new terminal and try again."
  kb_note_missing "$human"; return 1
}

# The assistant itself. Anthropic ship an installer for macOS and Linux, so use
# theirs rather than inventing a second way to install their product.
kb_install_claude_code() {
  if command -v claude >/dev/null 2>&1; then ok "Claude Code is already here"; return 0; fi
  if [ -x "$HOME/.local/bin/claude" ]; then
    export PATH="$HOME/.local/bin:$PATH"; kb_persist_path
    ok "Claude Code is already here"; return 0
  fi
  log "Installing Claude Code..."
  export PATH="$HOME/.local/bin:$PATH"
  curl -fsSL https://claude.ai/install.sh 2>/dev/null | bash >/dev/null 2>&1
  kb_persist_path
  if command -v claude >/dev/null 2>&1; then ok "Claude Code installed"; return 0; fi
  warn "Claude Code did not become usable. Open a new terminal and run: claude --version"
  kb_note_missing "Claude Code"; return 1
}

# Everything a hub needs on somebody's own computer. Reports what is still missing
# in KB_MISSING instead of stopping, because a half-wired machine that says which
# half is far more useful than one that quit on the first problem.
kb_install_prereqs() {
  say "Checking what this computer needs"
  KB_MISSING=""
  # git: a hub IS a git folder. node: several hub tools are node programs.
  kb_install_one git  git    git   "Git"     || true
  kb_install_one node nodejs node  "Node.js" || true
  kb_install_claude_code || true
  KB_MISSING="${KB_MISSING# }"
}

# kb_copy_starter_hub <path> <starter-repo> [folder-inside-it]
#
# Lay down a product's real starter folder, fetched from its own public repo.
#
# This exists because of a bug worth remembering. The first version of the Windows
# create path INVENTED a hub: a short AGENTS.md written from scratch. Meanwhile the
# book's kit already ships starter-hub/, a proper one with context/, skills/,
# procedures.md, decisions.md, inbox/ and prompts/, which the chapters then walk the
# reader through filling in. A reader would have got a folder that did not match the
# book in their hands, and every instruction like "open context/about-me.md" would
# have failed on a file that was never there.
#
# Nothing here may invent content a product already ships. Generic on purpose: the
# caller names the repository and the folder, so this stays the shared floor.
kb_copy_starter_hub() {
  local path="${1:-}" repo="${2:-}" sub="${3:-starter-hub}" tmp f base
  [ -n "$path" ] && [ -n "$repo" ] || return 1
  tmp="$(mktemp -d 2>/dev/null)" || return 1

  if ! git clone --depth 1 --quiet "$repo" "$tmp" >/dev/null 2>&1; then rm -rf "$tmp"; return 1; fi
  if [ ! -d "$tmp/$sub" ]; then rm -rf "$tmp"; return 1; fi

  mkdir -p "$path"
  # Top level only, and never over something already there, so a second run cannot
  # tread on a sentence the person has already written about themselves. The
  # .[!.]* pattern catches dotfiles without matching . or .. themselves.
  for f in "$tmp/$sub"/* "$tmp/$sub"/.[!.]*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ -e "$path/$base" ] && continue
    cp -R "$f" "$path/" 2>/dev/null || true
  done
  rm -rf "$tmp"
  return 0
}

# kb_new_hub <path> [their-existing-repo-url] [starter-repo] [folder-inside-it]
#
# There is no hub on this computer. Make one. Two shapes, because people arrive in
# two states: they already keep a hub in a git repository somewhere and this is
# simply another machine, or they have nothing at all and today is day one.
#
# On day one the folder is COPIED from the product's own starter, never written
# from imagination. See kb_copy_starter_hub for what that cost us.
kb_new_hub() {
  local path="${1:-}" repo_url="${2:-}" starter_repo="${3:-}" starter_path="${4:-starter-hub}"
  [ -n "$path" ] || { warn "kb_new_hub needs somewhere to put it"; return 1; }

  if [ -e "$path" ] && [ -n "$(ls -A "$path" 2>/dev/null)" ] && ! kb_hub_looks_real "$path"; then
    warn "$path already exists and has things in it, but it is not a hub.
   Pick an empty folder, or one that does not exist yet."
    return 1
  fi

  if [ -n "$repo_url" ]; then
    say "Getting your hub from $repo_url"
    mkdir -p "$(dirname "$path")"
    if ! git clone "$repo_url" "$path"; then
      warn "Could not copy that repository. If it is a private one, sign in first
   (run: gh auth login) and try again. The address I tried was $repo_url"
      return 1
    fi
    ok "your hub is now at $path"
    return 0
  fi

  say "Starting a new hub at $path"
  mkdir -p "$path" || { warn "Could not make the folder $path"; return 1; }

  if [ -n "$starter_repo" ]; then
    log "fetching the starter folder..."
    if kb_copy_starter_hub "$path" "$starter_repo" "$starter_path"; then
      ok "your hub starts with the real starter folder, the one the book fills in chapter by chapter"
    else
      # Loud, and with the way out in the same breath. A hub of the wrong shape
      # sends somebody looking for files the book names and they do not have,
      # which is a worse hour than being told plainly here.
      warn "I could not fetch the starter folder from $starter_repo
   so I am making a bare hub instead. It works, but it does NOT have the files the
   book walks you through (context/, skills/, procedures.md and the rest).
   To put that right: open that address in a browser, use the green Code button ->
   Download ZIP, and copy the starter-hub folder from inside it into $path"
    fi
  fi

  if [ ! -d "$path/.git" ]; then
    git -C "$path" init -q || { warn "Could not start a git folder at $path."; return 1; }
  fi
  # Returns early when the starter already brought one, so the product's own
  # index survives instead of being replaced by a blank.
  kb_seed_memory_index "$path"
  ok "your hub is now at $path"
  return 0
}
