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
#   curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2/setup-hub.sh | bash
#
# Options (all optional):
#   --hub <path>            where the hub is, or should go     (default: ~/hub)
#   --repo <git url>        a hub you already keep, to fetch
#   --starter-repo <url>    the product whose starter folder a new hub begins as
#   --starter-path <name>   the folder inside that repo        (default: starter-hub)
#   --skip-prereqs          do not install anything, just wire it up
#   --sources <list>        which AI tools may be synced from this machine, as a
#                           comma list (e.g. claude,codex). "" means none. Without
#                           it, every tool this kit can read that is found here.
#
# Safe to run as many times as you like. It never deletes a memory.
# =============================================================================
set -uo pipefail

KB_TAG="setup"
export KB_TAG

# WHICH BRANCH THIS SCRIPT PULLS ITS LIBRARY FROM, in one place, because getting
# it wrong is invisible. A v2 script that fetches v1/lib.sh runs v1's code and
# behaves exactly like v1, so a whole line of work reaches nobody and every test
# that pipes from the network still passes. Overridable so a test can point at a
# branch without editing this file.
KB_BRANCH="${KB_BRANCH:-v2}"

HUB=""
REPO_URL=""
# The book's kit, matching the default windows/setup-hub.ps1 has carried since it
# existed. Without one, an update run fetched no tools, so the notebook step further
# down had no runner to schedule. Another product overrides it with --starter-repo.
STARTER_REPO="https://github.com/MichaelZelbel/teach-it-once-kit.git"
STARTER_PATH="starter-hub"
SKIP_PREREQS=0
SOURCES=""
SOURCES_SET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --hub)          HUB="${2:-}";          shift 2 ;;
    --repo)         REPO_URL="${2:-}";     shift 2 ;;
    --starter-repo) STARTER_REPO="${2:-}"; shift 2 ;;
    --starter-path) STARTER_PATH="${2:-starter-hub}"; shift 2 ;;
    --skip-prereqs) SKIP_PREREQS=1;        shift ;;
    --sources)      SOURCES="${2:-}"; SOURCES_SET=1; shift 2 ;;
    --sources=*)    SOURCES="${1#--sources=}"; SOURCES_SET=1; shift ;;
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

# THE FETCH IS CHECKED BEFORE IT IS RUN, and it was not until 2026-08-29. This used to
# read `if eval "$(curl ...)"`, and `eval ""` SUCCEEDS, so a machine with no network took
# the first branch, loaded nothing, and fell straight into the refusal below. The copy
# sitting beside this very script was never tried: the fallback under it had never once
# been reachable. A reader on a plane, behind a captive portal or behind a company proxy
# was told to check their internet connection while a perfectly good library lay next to
# the file they had just downloaded.
KB_LOADED=0
KB_LIB_TEXT="$(curl -fsSL "https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/$KB_BRANCH/lib.sh" 2>/dev/null)"
if [ -n "$KB_LIB_TEXT" ] && eval "$KB_LIB_TEXT" 2>/dev/null; then
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
# and the published branch are published by two separate acts, so either can be ahead.
for fn in kb_install_prereqs kb_new_hub kb_copy_starter_hub kb_link_ai_memory kb_install_hub_cli \
          kb_install_hub_tools kb_install_prompt_harvest kb_sync_report kb_write_prompt_sources \
          kb_update_hub kb_connect_notebook; do
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
  # The starter can grow after a hub is born (dev/ and its .gitignore arrived
  # 2026-08-19). Top up whatever is missing, top level only and never over
  # anything already there, so a re-run delivers new rooms without treading on
  # a word the person wrote. The one exception is .gitignore, which is merged
  # line-by-line inside kb_copy_starter_hub: every hub already has one, and
  # skip-if-present would keep the dev/ fence from ever reaching an old hub.
  # Before this line, an update run never looked at the starter at all, so a
  # new room only ever reached new hubs.
  TOPUP_BEFORE="$(ls -A "$HUB" 2>/dev/null | sort)"
  kb_copy_starter_hub "$HUB" "$STARTER_REPO" "$STARTER_PATH" || true
  TOPUP_AFTER="$(ls -A "$HUB" 2>/dev/null | sort)"
  if [ "$TOPUP_BEFORE" != "$TOPUP_AFTER" ]; then
    ok "the starter grew since this hub was made; added what was missing, touched nothing else."
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
#
#    First, which AI tools live here and which may be synced. The choice lands on
#    this device before any wiring runs, so everything below obeys it, and the
#    person is told what will be read BEFORE it is read.
# -----------------------------------------------------------------------------
if [ "$SOURCES_SET" -eq 1 ]; then
  KB_SYNC_SOURCES="$SOURCES"
  export KB_SYNC_SOURCES
  kb_write_prompt_sources "$SOURCES"
fi
kb_sync_report

kb_link_ai_memory   "$HUB"    # the one memory every machine shares
kb_install_hub_cli  "$HUB"    # the hub's own commands, on PATH, from any folder
kb_install_hub_tools "$HUB" "$STARTER_REPO"   # the kit's own programs, on this machine
kb_install_prompt_harvest "$HUB"  # the daily job that files what you type to an AI here
# The notebook, and the one thing about it that has to travel: connect it once and the
# connection lives in the folder, so the next computer only ever types the passphrase.
# Quiet and complete for the reader who never connects one - which is most of the book.
kb_connect_notebook "$HUB"

kb_wire_skills "$HUB"   # one real room, links to it, and it counts what it wired

# -----------------------------------------------------------------------------
# 5. What just happened, in words.
# -----------------------------------------------------------------------------
# Built from what actually happened on THIS machine, never from the promise.
# The old text claimed every assistant shares one memory, on machines where one
# tool (or none) had been wired. The truth lets a person see a gap; the promise
# hides it.
say "Done"
if [ "$IS_NEW" -eq 1 ]; then
  echo "Your hub is at:"
else
  echo "This computer is up to date and wired in. Your hub is at:"
fi
cat <<EOF

  $HUB

EOF
kb_sync_report
cat <<EOF

Two things worth knowing:

  * Open a NEW terminal window before you use the hub commands, so it picks up
    what was just installed.
  * Your hub travels between machines through git. Push it from here, and run
    this same command on the next machine to pick it up there. To change which
    AI tools are read on this machine, edit HUB_PROMPT_SOURCES in ~/.hub/device.env
EOF

if [ -n "${KB_MISSING:-}" ]; then
  warn "I could not install these, so some things will not work until they are here: $KB_MISSING"
fi
