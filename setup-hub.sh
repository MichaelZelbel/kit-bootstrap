#!/usr/bin/env bash
# =============================================================================
# kit-bootstrap / setup-hub.sh   -   the macOS and Linux twin of HubSetup.exe
#
# One command that sets up a hub, whatever state this computer is in. It decides
# between the two jobs by LOOKING, never by asking:
#
#   nothing here yet  -> INSTALL   (fetch what is missing, then make the hub)
#   already have one  -> UPDATE    (bring it current, then re-check the wiring)
#
# Why this file exists. On 2026-08-09 Windows got a real installer, and the same
# morning the Windows side quietly grew two abilities this side never had:
# installing prerequisites, and creating a hub from nothing. join.sh only ever
# JOINED, and stopped with an error when there was no hub to join. So for a day a
# Mac reader on a fresh machine got an error and a Windows reader got a finished
# setup. Michael saw the asymmetry and asked whether the .exe was the odd one out.
# It was not. This is the other half catching up.
#
# The platforms differ on purpose and that is the whole point. A terminal command
# IS the native way to install things on macOS and Linux - Homebrew installs
# itself exactly this way - and it is NOT the native way on Windows. What is kept
# identical is the promise: one thing to run, no decisions, it works out the rest.
#
#   curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v1/setup-hub.sh | bash
#
# Options (all optional):
#   --hub <path>            where the hub is, or should go     (default: ~/hub)
#   --repo <git url>        a hub you already keep, to fetch
#   --starter-repo <url>    the product whose starter folder a new hub begins as
#   --starter-path <name>   the folder inside that repo        (default: starter-hub)
#   --skip-prereqs          do not install anything, just wire it up
#
# Safe to run as many times as you like. It never deletes a memory.
# =============================================================================
set -uo pipefail

KB_TAG="setup"
export KB_TAG

HUB=""
REPO_URL=""
STARTER_REPO=""
STARTER_PATH="starter-hub"
SKIP_PREREQS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --hub)          HUB="${2:-}";          shift 2 ;;
    --repo)         REPO_URL="${2:-}";     shift 2 ;;
    --starter-repo) STARTER_REPO="${2:-}"; shift 2 ;;
    --starter-path) STARTER_PATH="${2:-starter-hub}"; shift 2 ;;
    --skip-prereqs) SKIP_PREREQS=1;        shift ;;
    -h|--help)      sed -n '2,35p' "$0" 2>/dev/null; exit 0 ;;
    # A bare path, so `... | bash -s -- ~/hub` keeps working the way join.sh did.
    *)              [ -z "$HUB" ] && HUB="$1"; shift ;;
  esac
done

# -----------------------------------------------------------------------------
# 1. The shared install code.
#
# Fetched from the network FIRST, then from a copy beside this file. That order
# is the point: a script somebody saved in March otherwise runs March's code on
# exactly the machine that has been neglected longest. Piped from curl there is
# no file on disk at all, so $0 is "bash"; checking that $0 is a real file is what
# stops us sourcing a stranger's lib.sh out of whatever folder they stood in.
# -----------------------------------------------------------------------------
KB_SELF=""
case "$0" in */*) [ -f "$0" ] && KB_SELF="$(cd "$(dirname "$0")" && pwd)" ;; esac

KB_LOADED=0
if eval "$(curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v1/lib.sh 2>/dev/null)" 2>/dev/null; then
  KB_LOADED=1
elif [ -n "$KB_SELF" ] && [ -f "$KB_SELF/lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$KB_SELF/lib.sh" && KB_LOADED=1
  printf '[setup] no network, so I am using the copy beside this script. It may be behind.\n' >&2
fi

if [ "$KB_LOADED" -ne 1 ] || ! command -v kb_find_hub >/dev/null 2>&1; then
  echo "[stop] I could not load the install code." >&2
  echo "       Check this computer can reach the internet, then run it again." >&2
  exit 1
fi

# Newer than the network copy is a real state, not a theoretical one: this script
# and the v1 branch are published by two separate acts, so either can be ahead.
for fn in kb_install_prereqs kb_new_hub kb_copy_starter_hub kb_link_ai_memory kb_install_hub_cli \
          kb_install_hub_tools kb_install_prompt_harvest; do
  if ! command -v "$fn" >/dev/null 2>&1; then
    echo "[stop] the install code on this computer is incomplete ($fn is missing)." >&2
    echo "       Run the newest command from https://github.com/MichaelZelbel/kit-bootstrap" >&2
    exit 1
  fi
done

say "Setting up your hub"

# -----------------------------------------------------------------------------
# 2. What this computer is missing. Git, Node.js, Claude Code.
# -----------------------------------------------------------------------------
KB_MISSING=""
[ "$SKIP_PREREQS" -eq 1 ] || kb_install_prereqs

# git is the one thing nothing else can work around: a hub is a git folder.
if ! command -v git >/dev/null 2>&1; then
  die "Git is not on this computer and I could not install it.
   On a Mac:   install Homebrew from https://brew.sh then run this again
   On Ubuntu:  sudo apt-get install -y git    then run this again"
fi

# -----------------------------------------------------------------------------
# 3. Install or update? Look, do not ask.
# -----------------------------------------------------------------------------
FOUND="$(kb_find_hub "$HUB" 2>/dev/null || true)"
IS_NEW=0

if [ -n "$FOUND" ]; then
  HUB="$FOUND"
  say "Found the hub already on this computer at $HUB"
  BEFORE="$(git -C "$HUB" rev-parse --short HEAD 2>/dev/null || true)"
  kb_update_hub "$HUB"
  AFTER="$(git -C "$HUB" rev-parse --short HEAD 2>/dev/null || true)"
  if [ -n "$BEFORE" ] && [ -n "$AFTER" ] && [ "$BEFORE" != "$AFTER" ]; then
    ok "it was out of date. Brought it up to date ($BEFORE to $AFTER)."
  fi
else
  IS_NEW=1
  [ -n "$HUB" ] || HUB="$HOME/hub"
  say "No hub on this computer yet, so I am making one"
  kb_new_hub "$HUB" "$REPO_URL" "$STARTER_REPO" "$STARTER_PATH" \
    || die "I could not make the hub. Read what it said just above."
  HUB="$(cd "$HUB" && pwd -P)"
fi

# -----------------------------------------------------------------------------
# 4. The wiring. Identical whether this was an install or an update, which is why
#    running it twice is a normal thing to do rather than a mistake.
# -----------------------------------------------------------------------------
kb_link_ai_memory   "$HUB"    # the one memory every machine shares
kb_install_hub_cli  "$HUB"    # the hub's own commands, on PATH, from any folder
kb_install_hub_tools "$HUB" "$STARTER_REPO"   # the kit's own programs, on this machine
kb_install_prompt_harvest "$HUB"  # the daily job that files what you type to an AI here

if [ -d "$HUB/.claude/skills" ] && [ ! -e "$HUB/.agents/skills" ]; then
  mkdir -p "$HUB/.agents"
  ln -sfn "$HUB/.claude/skills" "$HUB/.agents/skills"
  ok "skills: assistants other than Claude Code can now read them too"
fi

# -----------------------------------------------------------------------------
# 5. What just happened, in words.
# -----------------------------------------------------------------------------
say "Done"
if [ "$IS_NEW" -eq 1 ]; then
  cat <<EOF
Your hub is at:

  $HUB

That folder is the brain your AI assistants share. Anything an assistant learns
about you is written into it, and every assistant on every machine you run this
on reads the same thing.

Two things worth knowing:

  * Open a NEW terminal window before you use the hub commands, so it picks up
    what was just installed.
  * Your hub travels between machines through git. Push it from here, and run
    this same command on the next machine to pick it up there.
EOF
else
  cat <<EOF
This computer is up to date and wired in. Your hub is at:

  $HUB

Its memory is shared with your other machines: what an assistant learns here
goes into that folder and travels with your next push, and what it learned
elsewhere is already here.

Open a NEW terminal window before using the hub commands.
EOF
fi

if [ -n "${KB_MISSING:-}" ]; then
  warn "I could not install these, so some things will not work until they are here: $KB_MISSING"
fi
