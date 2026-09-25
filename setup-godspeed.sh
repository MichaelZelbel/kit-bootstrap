#!/usr/bin/env bash
# =============================================================================
# kit-bootstrap / setup-godspeed.sh   -   the macOS and Linux twin of GodspeedSetup.exe
#
# One command that sets up a mission control, whatever state this computer is in. It decides
# between the two jobs by LOOKING, never by asking:
#
#   nothing here yet  -> INSTALL   (fetch what is missing, then make the mission control)
#   already have one  -> UPDATE    (bring it current, then re-check the wiring)
#
# Why this file exists. On 2026-08-09 Windows got a real installer, and the same
# morning the Windows side quietly grew two abilities this side never had:
# installing prerequisites, and creating a mission control from nothing. join.sh only ever
# JOINED, and stopped with an error when there was no mission control to join. So for a day a
# Mac reader on a fresh machine got an error and a Windows reader got a finished
# setup. Michael saw the asymmetry and asked whether the .exe was the odd one out.
# It was not. This is the other half catching up.
#
# The platforms differ on purpose and that is the whole point. A terminal command
# IS the native way to install things on macOS and Linux - Homebrew installs
# itself exactly this way - and it is NOT the native way on Windows. What is kept
# identical is the promise: one thing to run, no decisions, it works out the rest.
#
#   curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2/setup-godspeed.sh | bash
#
# Options (all optional):
#   --godspeed <path>            where the mission control is, or should go     (default: ~/godspeed)
#                           Not under Documents, Desktop, Pictures or any cloud drive
#                           folder: those are refused, with the reason.
#   --repo <git url>        a mission control you already keep, to fetch
#   --starter-repo <url>    the product whose starter folder a new mission control begins as
#   --starter-path <name>   the folder inside that repo        (default: starter-godspeed)
#   --skip-prereqs          do not install anything, just wire it up
#   --sources <list>        which AI tools have their conversations copied into the
#                           mission control from this machine, as a comma list (claude, codex,
#                           hermes, opencode). "" means none. Without it, a machine
#                           getting its first mission control copies nothing, and a machine that
#                           already has one keeps the choice it made before.
#   --beside                put a SECOND mission control at --godspeed and leave this computer working
#                           from the one it already has. Needs --godspeed, and needs a mission control
#                           already here to sit beside. For a work mission control next to a
#                           personal one, for trying a mission control before moving into it, and
#                           for a clean mission control to record on a machine that carries a full
#                           one. kb_beside in lib.sh lists what it leaves alone.
#   --only menerio          run ONE step and leave the rest of this computer alone: ask
#                           about Menerio, store the key, and give every assistant here
#                           the connection. For the reader who said no on the day. It
#                           needs a mission control already on this computer.
#   --only gmail            retired (2026-09-22): refreshes the mail tool and says that
#                           Gmail is now connected by asking an assistant "Connect Gmail
#                           for me". It connects nothing itself.
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

GODSPEED=""
REPO_URL=""
# The book's kit, matching the default windows/setup-godspeed.ps1 has carried since it
# existed. Without one, an update run fetched no tools, so the notebook step further
# down had no runner to schedule. Another product overrides it with --starter-repo.
STARTER_REPO="https://github.com/MichaelZelbel/godspeed-mission-control.git"
STARTER_PATH="starter-godspeed"
SKIP_PREREQS=0
SOURCES=""
SOURCES_SET=0
BESIDE=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --godspeed)          GODSPEED="${2:-}";          shift 2 ;;
    --repo)         REPO_URL="${2:-}";     shift 2 ;;
    --starter-repo) STARTER_REPO="${2:-}"; shift 2 ;;
    --starter-path) STARTER_PATH="${2:-starter-godspeed}"; shift 2 ;;
    --skip-prereqs) SKIP_PREREQS=1;        shift ;;
    --beside)       BESIDE=1;              shift ;;
    --only)         ONLY="${2:-}";         shift 2 ;;
    --only=*)       ONLY="${1#--only=}";   shift ;;
    --sources)      SOURCES="${2:-}"; SOURCES_SET=1; shift 2 ;;
    --sources=*)    SOURCES="${1#--sources=}"; SOURCES_SET=1; shift ;;
    -h|--help)      sed -n '2,51p' "$0" 2>/dev/null; exit 0 ;;
    # A bare path, so `... | bash -s -- ~/godspeed` keeps working the way join.sh did.
    *)              [ -z "$GODSPEED" ] && GODSPEED="$1"; shift ;;
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

if [ "$KB_LOADED" -ne 1 ] || ! command -v kb_find_godspeed >/dev/null 2>&1; then
  echo "[stop] I could not load the install code." >&2
  echo "       Check this computer can reach the internet, then run it again." >&2
  exit 1
fi

# Newer than the network copy is a real state, not a theoretical one: this script
# and the published branch are published by two separate acts, so either can be ahead.
for fn in kb_install_prereqs kb_new_godspeed kb_copy_starter_godspeed kb_link_ai_memory kb_install_godspeed_cli \
          kb_install_godspeed_tools kb_install_prompt_harvest kb_sync_report kb_write_prompt_sources \
          kb_update_godspeed kb_connect_notebook kb_wire_skills kb_point_hermes_at_godspeed \
          kb_hermes_approvals kb_hermes_one_memory kb_refuse_godspeed_path kb_default_godspeed_dir \
          kb_beside kb_same_path kb_only_menerio kb_only_gmail kb_gmail_retired; do
  if ! command -v "$fn" >/dev/null 2>&1; then
    echo "[stop] the install code on this computer is incomplete ($fn is missing)." >&2
    echo "       Run the newest command from https://github.com/MichaelZelbel/kit-bootstrap" >&2
    exit 1
  fi
done

# -----------------------------------------------------------------------------
# 1b. One step only, when that is what was asked for.
#
# Sits BEFORE the prerequisites on purpose. A reader who comes back for Menerio has a
# working mission control already, and re-checking Git, Node and Hermes, pulling the folder and
# re-running every wiring step is not what they came for. kb_only_menerio in lib.sh
# says what the one step runs. It needs a mission control to connect, so it never makes one.
# -----------------------------------------------------------------------------
if [ -n "$ONLY" ]; then
  case "$ONLY" in menerio|gmail) ;; *) die "--only knows two steps: menerio and gmail. You typed: $ONLY" ;; esac
  if [ "$BESIDE" -eq 1 ]; then KB_BESIDE=1; export KB_BESIDE; fi
  FOUND="$(kb_find_godspeed "$GODSPEED" 2>/dev/null || true)"
  [ -n "$FOUND" ] || die "there is no mission control on this computer yet, so there is nothing to connect. Run this without --only first, and it will make one."
  if [ -n "$GODSPEED" ] && ! kb_same_path "$FOUND" "$GODSPEED"; then
    die "you asked for the mission control at $GODSPEED, and I could not find a mission control there. This computer works from $FOUND. Leave off --godspeed to connect that one."
  fi
  if [ "$ONLY" = "gmail" ]; then kb_only_gmail "$FOUND" "$STARTER_REPO"
  else kb_only_menerio "$FOUND" "$STARTER_REPO"; fi
  exit 0
fi

say "Setting up Godspeed Mission Control"

# -----------------------------------------------------------------------------
# 2. What this computer is missing. Git, Node.js, Hermes.
# -----------------------------------------------------------------------------
KB_MISSING=""
[ "$SKIP_PREREQS" -eq 1 ] || kb_install_prereqs

# git is the one thing nothing else can work around: a mission control is a git folder.
if ! command -v git >/dev/null 2>&1; then
  die "Git is not on this computer and I could not install it.
   On a Mac:   install Homebrew from https://brew.sh then run this again
   On Ubuntu:  sudo apt-get install -y git    then run this again"
fi

# -----------------------------------------------------------------------------
# 3. Install or update? Look, do not ask.
# -----------------------------------------------------------------------------
# BESIDE means "do not ask this machine where its mission control is". kb_find_godspeed answers that
# question, and on a machine that already works from one it answers with THAT one: it
# reads $GODSPEED_DIR before it looks at anything else. So an explicit --godspeed naming a folder
# that did not exist yet used to fall straight through to the mission control already here, which
# was then brought up to date under a green tick while the folder actually asked for was
# never made and nothing said why. A beside run looks at the path it was given and at
# nothing else.
OTHER=""
if [ "$BESIDE" -eq 1 ]; then
  [ -n "$GODSPEED" ] || die "--beside needs --godspeed as well. It puts a mission control in a place you name and leaves this computer working from the one it already has, so it has to be told where. Example: --beside --godspeed $(kb_default_godspeed_dir)"
  OTHER="$(kb_find_godspeed 2>/dev/null || true)"
  [ -n "$OTHER" ] || die "there is no mission control on this computer yet, so there is nothing for a second one to sit beside. Run this without --beside and it will make the first one."
  ! kb_same_path "$OTHER" "$GODSPEED" || die "$GODSPEED is the mission control this computer already works from, so it cannot sit beside itself. Run this without --beside to bring it up to date."
  KB_BESIDE=1
  export KB_BESIDE
  say "This computer works from $OTHER and keeps working from it. The new mission control will sit beside it."
  FOUND=""
  kb_godspeed_looks_real "$GODSPEED" && FOUND="$(cd "$GODSPEED" && pwd -P)"
else
  FOUND="$(kb_find_godspeed "$GODSPEED" 2>/dev/null || true)"
  if [ -n "$FOUND" ] && [ -n "$GODSPEED" ] && ! kb_same_path "$FOUND" "$GODSPEED"; then
    die "you asked for a mission control at $GODSPEED, but this computer already works from $FOUND. To put a second mission control at $GODSPEED and leave $FOUND in charge of this computer, add --beside. To bring $FOUND up to date instead, leave off --godspeed."
  fi
fi
IS_NEW=0

if [ -n "$FOUND" ]; then
  GODSPEED="$FOUND"
  say "Found your mission control already on this computer at $GODSPEED"
  BEFORE="$(git -C "$GODSPEED" rev-parse --short HEAD 2>/dev/null || true)"
  kb_update_godspeed "$GODSPEED"
  AFTER="$(git -C "$GODSPEED" rev-parse --short HEAD 2>/dev/null || true)"
  if [ -n "$BEFORE" ] && [ -n "$AFTER" ] && [ "$BEFORE" != "$AFTER" ]; then
    ok "it was out of date. Brought it up to date ($BEFORE to $AFTER)."
  fi
  # The starter can grow after a mission control is born (dev/ and its .gitignore arrived
  # 2026-08-19). Top up whatever is missing, top level only and never over
  # anything already there, so a re-run delivers new rooms without treading on
  # a word the person wrote. The one exception is .gitignore, which is merged
  # line-by-line inside kb_copy_starter_godspeed: every mission control already has one, and
  # skip-if-present would keep the dev/ fence from ever reaching an old mission control.
  # Before this line, an update run never looked at the starter at all, so a
  # new room only ever reached new mission controls.
  TOPUP_BEFORE="$(ls -A "$GODSPEED" 2>/dev/null | sort)"
  kb_copy_starter_godspeed "$GODSPEED" "$STARTER_REPO" "$STARTER_PATH" || true
  TOPUP_AFTER="$(ls -A "$GODSPEED" 2>/dev/null | sort)"
  if [ "$TOPUP_BEFORE" != "$TOPUP_AFTER" ]; then
    ok "the starter grew since this mission control was made; added what was missing, touched nothing else."
  fi
else
  IS_NEW=1
  [ -n "$GODSPEED" ] || GODSPEED="$(kb_default_godspeed_dir)"
  REFUSED="$(kb_refuse_godspeed_path "$GODSPEED")"
  [ -z "$REFUSED" ] || die "I will not put your mission control at $GODSPEED: $REFUSED"
  if [ "$BESIDE" -eq 1 ]; then say "Making your mission control at $GODSPEED"
  else say "No mission control on this computer yet, so I am making one"; fi
  kb_new_godspeed "$GODSPEED" "$REPO_URL" "$STARTER_REPO" "$STARTER_PATH" \
    || die "I could not make your mission control. Read what it said just above."
  GODSPEED="$(cd "$GODSPEED" && pwd -P)"
fi

# -----------------------------------------------------------------------------
# 4. The wiring. Identical whether this was an install or an update, which is why
#    running it twice is a normal thing to do rather than a mistake.
#
#    First, which AI tools live here and which may be synced. The choice lands on
#    this device before any wiring runs, so everything below obeys it, and the
#    person is told what will be read BEFORE it is read.
# -----------------------------------------------------------------------------
# A machine getting its first mission control copies no conversations until its owner names
# the tools, the same as the Windows wizard, whose boxes start unticked there. Copying
# is the one step that pushes words typed to other programs into a repository, so it
# is asked for, never assumed. A machine that already works from a mission control (an update, or
# --beside) keeps whatever it recorded or did before, so an update never switches
# anything off behind anyone's back.
if [ "$SOURCES_SET" -eq 0 ] && [ "$IS_NEW" -eq 1 ] && [ "$BESIDE" -eq 0 ]    && ! grep -q '^[[:space:]]*GODSPEED_PROMPT_SOURCES=' "$HOME/.godspeed/device.env" 2>/dev/null; then
  SOURCES=""
  SOURCES_SET=1
fi
if [ "$SOURCES_SET" -eq 1 ]; then
  KB_SYNC_SOURCES="$SOURCES"
  export KB_SYNC_SOURCES
  kb_write_prompt_sources "$SOURCES"
fi
kb_sync_report

kb_link_ai_memory   "$GODSPEED"    # the one memory every machine shares
kb_install_godspeed_cli  "$GODSPEED"    # the mission control's own commands, on PATH, from any folder
kb_install_godspeed_tools "$GODSPEED" "$STARTER_REPO"   # the kit's own programs, on this machine
kb_install_prompt_harvest "$GODSPEED"  # the daily job that files what you type to an AI here
# The notebook, and the one thing about it that has to travel: connect it once and the
# connection lives in the folder, so the next computer only ever types the passphrase.
# Quiet and complete for the reader who never connects one - which is most of the book.
kb_connect_notebook "$GODSPEED"
# The mail tool, known to every assistant and connected to nothing (email is optional).
command -v kb_wire_mail >/dev/null 2>&1 && kb_wire_mail "$GODSPEED"
# Email is never asked about during an install or an update (THE GMAIL STEP, RETIRED, in lib.sh).

kb_wire_skills "$GODSPEED"   # one real room, links to it, and it counts what it wired

# Where Hermes works. terminal.cwd, never `workspace`, and proved by a file read
# rather than by reading the setting back. See the long note above the function:
# four of the six known ways to do this are silent no-ops and the kit shipped one.
kb_point_hermes_at_godspeed "$GODSPEED"

# The leash. A translation of the Claude permissions file, not a rename: Hermes
# already allows every command the kit runs, so this writes no allowlist at all and
# only closes the gaps its own floor leaves open. Measured, both ways.
kb_hermes_approvals

# One memory. Hermes keeps its own beside the mission control's unless told not to, and a second
# memory nothing can see is how an assistant starts telling you what used to be true.
kb_hermes_one_memory

# -----------------------------------------------------------------------------
# 5. What just happened, in words.
# -----------------------------------------------------------------------------
# Built from what actually happened on THIS machine, never from the promise.
# The old text claimed every assistant shares one memory, on machines where one
# tool (or none) had been wired. The truth lets a person see a gap; the promise
# hides it.
say "Done"
if [ "$BESIDE" -eq 1 ]; then
  echo "This second mission control is ready at:"
elif [ "$IS_NEW" -eq 1 ]; then
  echo "Your mission control is at:"
else
  echo "This computer is up to date and wired in. Your mission control is at:"
fi
cat <<EOF

  $GODSPEED

EOF
if [ "$BESIDE" -eq 1 ]; then
  cat <<EOF
It has its own folders, its own git history and its own assistant memory.
This computer still works from $OTHER, which keeps its commands, the daily
job, the hourly notebook job and the folder Hermes starts in. To work in the new
one, open a terminal or an assistant inside it.

EOF
fi
kb_sync_report
cat <<EOF

Worth knowing:

  * Open a NEW terminal window before you use its commands, so it picks up
    what was just installed.
  * Your mission control travels between machines through git. Push it from here, and run
    this same command on the next machine to pick it up there. To change which
    AI tools have their conversations copied from this machine, run it again with
    --sources, or edit GODSPEED_PROMPT_SOURCES in ~/.godspeed/device.env
EOF
command -v kb_mail_note >/dev/null 2>&1 && kb_mail_note

if [ -n "${KB_MISSING:-}" ]; then
  warn "I could not install these, so some things will not work until they are here: $KB_MISSING"
fi
