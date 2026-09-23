#!/usr/bin/env bash
# =============================================================================
# kit-bootstrap / join.sh   -   "I already have a mission control. This is another machine."
#
# There are two jobs, not two audiences, and mixing that up cost us a real bug.
#
#   CREATE  build a mission control for someone who has none. That is server/install.sh in
#           the book's kit: it makes an account, installs the assistant, signs
#           in to GitHub, makes the repository, asks three questions.
#   JOIN    wire a machine you already own into a mission control that already exists. That
#           is this file.
#
# Until 2026-08-09 only CREATE existed in the kit, and JOIN existed only inside
# Michael's private repo. So a reader who bought a second laptop had nothing at
# all, and the same wiring had to be written twice. D-092 says install code lives
# here once. This is that rule applied to the half nobody had written.
#
# Usage:
#   bash join.sh [path-to-your-mc-folder]      (default: ~/godspeed, or $GODSPEED)
#   bash join.sh --sources claude,codex         only these AI tools may be synced
#   bash join.sh --sources ""                   sync nothing from this machine
#   bash join.sh --only menerio                 just connect Menerio, change nothing else
#
# Piped from curl there is no keyboard to ask questions on, so this stays
# non-interactive: it says plainly which AI tools it found and which it will
# read, and --sources (or GODSPEED_PROMPT_SOURCES in ~/.godspeed/device.env) is how a
# person changes that. The Windows installer asks the same question with
# checkboxes, because there a wizard is the native way.
#
# Safe to run as many times as you like. It never deletes a memory.
# =============================================================================
set -uo pipefail

GODSPEED_ARG=""
SOURCES=""
SOURCES_SET=0
ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sources)   SOURCES="${2:-}"; SOURCES_SET=1; shift 2 ;;
    --sources=*) SOURCES="${1#--sources=}"; SOURCES_SET=1; shift ;;
    --only)      ONLY="${2:-}"; shift 2 ;;
    --only=*)    ONLY="${1#--only=}"; shift ;;
    *)           [ -z "$GODSPEED_ARG" ] && GODSPEED_ARG="$1"; shift ;;
  esac
done

KB_TAG="join"
export KB_TAG

# Load the shared code. Piped straight from the web ("curl ... | bash") there is no
# file on disk, so $0 is "bash" and its directory is wherever the reader happened to
# be standing. Checking that $0 is a real file is what stops us sourcing a stranger's
# lib.sh out of the current folder.
KB_SELF=""
case "$0" in */*) [ -f "$0" ] && KB_SELF="$(cd "$(dirname "$0")" && pwd)" ;; esac
if [ -n "$KB_SELF" ] && [ -f "$KB_SELF/lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$KB_SELF/lib.sh"
else
  eval "$(curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v2/lib.sh)" \
    || { echo "[stop] could not load the shared install code from the network." >&2
         echo "       Download join.sh and lib.sh into the same folder and run it from there." >&2
         exit 1; }
fi

# Which mission control? A machine that has one already knows where it is, so look before asking.
# Only when nothing is found do we make the reader type a path.
GODSPEED="$(kb_find_godspeed "$GODSPEED_ARG")" || die "I could not find a mission control on this machine.
I looked where you pointed me, at the folder your assistant's memory is linked to,
and in the usual places (~/godspeed, /root/godspeed, C:\\godspeed). If yours is somewhere else,
pass the path: bash join.sh /path/to/your/godspeed
If you have not got one yet, clone it first, then run this again."

# One step only, when that is what was asked for. The same switch setup-godspeed.sh takes,
# and kb_only_menerio in lib.sh says what the one step runs and why it exists.
if [ -n "$ONLY" ]; then
  case "$ONLY" in menerio|gmail) ;; *) die "--only knows two steps: menerio and gmail. You typed: $ONLY" ;; esac
  command -v "kb_only_$ONLY" >/dev/null 2>&1 || die "the install code on this computer is older than this script, so it has no single $ONLY step yet. Run the newest command from https://github.com/MichaelZelbel/kit-bootstrap"
  "kb_only_$ONLY" "$GODSPEED" "${KB_TOOLS_REPO:-}"
  exit 0
fi

say "Joining this machine to the mission control at $GODSPEED"

# 0. Which AI tools live here, and which may be synced. The choice is recorded on
#    this device before any wiring runs, so everything below obeys it, and the
#    person is told what will be read BEFORE it is read, not after.
if [ "$SOURCES_SET" -eq 1 ]; then
  KB_SYNC_SOURCES="$SOURCES"
  export KB_SYNC_SOURCES
  kb_write_prompt_sources "$SOURCES"
fi
kb_sync_report

# 1. Get the latest of everything, because a join that leaves you on last month's
#    memory looks exactly like a join that worked. This is also what updates an
#    older installation on a machine you have not touched in a while.
kb_update_godspeed "$GODSPEED"

# 2. The shared memory. This is the whole point of joining.
kb_link_ai_memory "$GODSPEED"

# 2b. The mission control's own commands, so `godspeed map ...` works from any folder on this
#     machine instead of only on the server where the deploy script installs them.
kb_install_godspeed_cli "$GODSPEED"

# 2c. The kit's own programs, on this machine rather than in the mission control folder (the mission control is a
#     folder of text files, and these are software). KB_TOOLS_REPO lets a product name its
#     own kit; without one there is nothing to fetch and the step does nothing.
kb_install_godspeed_tools "$GODSPEED" "${KB_TOOLS_REPO:-}"

# 2d. The daily job that files what you type to an AI on this machine into the mission control.
#     Joining a machine has to wire this, because a job you install by hand only ever
#     covers the machine you were sitting at when you thought of it.
kb_install_prompt_harvest "$GODSPEED"

# 2e. The notebook. A joined machine is exactly the machine this step was made for: the
#     credentials travel inside the folder, so if the mission control carries them this unseals and
#     wires the sync here too, and asks nothing. Sits after 2c on purpose, because it
#     schedules the runner that step just installed. Quiet and complete for the reader
#     who never connects one, and piped from curl with no keyboard it stays silent.
kb_connect_notebook "$GODSPEED"
# 2f. The mail tool, known to every assistant here and connected to nothing. A Gmail
#     connection made on another computer lives in the mission control's locked store, so it works here
#     as soon as this computer can open the store; there is no second Google sign-in.
command -v kb_wire_mail >/dev/null 2>&1 && kb_wire_mail "$GODSPEED"

# 3. Skills, if this mission control keeps them where the assistants other than Claude Code
#    can be pointed at them. Harmless when it has none.
if [ -d "$GODSPEED/.claude/skills" ] && [ ! -e "$GODSPEED/.agents/skills" ]; then
  mkdir -p "$GODSPEED/.agents"
  ln -sfn "$GODSPEED/.claude/skills" "$GODSPEED/.agents/skills"
  ok "skills: assistants other than Claude Code can now read them too"
fi

# The completion text is built from what actually happened on THIS machine,
# never from the promise. The old text here claimed "nothing is stored inside
# one AI tool any more" on every machine, including ones where only Claude Code
# (or nothing at all) had been wired. A person who is told the truth can fix a
# gap; a person who is told the promise cannot even see one.
say "Done"
echo "Your mission control on this machine is $GODSPEED"
echo ""
kb_sync_report
cat <<EOF

Anything synced travels between your machines with the mission control's git push and pull,
so keep doing what you already do with the folder. To change which AI tools are
read on this machine later: run this again with --sources, or edit
GODSPEED_PROMPT_SOURCES in ~/.godspeed/device.env
EOF
command -v kb_mail_note >/dev/null 2>&1 && kb_mail_note
