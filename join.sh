#!/usr/bin/env bash
# =============================================================================
# kit-bootstrap / join.sh   -   "I already have a hub. This is another machine."
#
# There are two jobs, not two audiences, and mixing that up cost us a real bug.
#
#   CREATE  build a hub for someone who has none. That is server/install.sh in
#           the book's kit: it makes an account, installs the assistant, signs
#           in to GitHub, makes the repository, asks three questions.
#   JOIN    wire a machine you already own into a hub that already exists. That
#           is this file.
#
# Until 2026-08-09 only CREATE existed in the kit, and JOIN existed only inside
# Michael's private repo. So a reader who bought a second laptop had nothing at
# all, and the same wiring had to be written twice. D-092 says install code lives
# here once. This is that rule applied to the half nobody had written.
#
# Usage:
#   bash join.sh [path-to-your-hub-folder]      (default: ~/hub, or $HUB)
#
# Safe to run as many times as you like. It never deletes a memory.
# =============================================================================
set -uo pipefail

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
  eval "$(curl -fsSL https://raw.githubusercontent.com/MichaelZelbel/kit-bootstrap/v1/lib.sh)" \
    || { echo "[stop] could not load the shared install code from the network." >&2
         echo "       Download join.sh and lib.sh into the same folder and run it from there." >&2
         exit 1; }
fi

# Which hub? A machine that has one already knows where it is, so look before asking.
# Only when nothing is found do we make the reader type a path.
HUB="$(kb_find_hub "${1:-}")" || die "I could not find a hub on this machine.
I looked where you pointed me, at the folder your assistant's memory is linked to,
and in the usual places (~/hub, /root/hub, C:\\hub). If yours is somewhere else,
pass the path: bash join.sh /path/to/your/hub
If you have not got one yet, clone it first, then run this again."

say "Joining this machine to the hub at $HUB"

# 1. Get the latest of everything, because a join that leaves you on last month's
#    memory looks exactly like a join that worked. This is also what updates an
#    older installation on a machine you have not touched in a while.
kb_update_hub "$HUB"

# 2. The shared memory. This is the whole point of joining.
kb_link_ai_memory "$HUB"

# 2b. The hub's own commands, so `hub map ...` works from any folder on this
#     machine instead of only on the server where the deploy script installs them.
kb_install_hub_cli "$HUB"

# 2c. The daily job that files what you type to an AI on this machine into the hub.
#     Joining a machine has to wire this, because a job you install by hand only ever
#     covers the machine you were sitting at when you thought of it.
kb_install_prompt_harvest "$HUB"

# 3. Skills, if this hub keeps them where the assistants other than Claude Code
#    can be pointed at them. Harmless when it has none.
if [ -d "$HUB/.claude/skills" ] && [ ! -e "$HUB/.agents/skills" ]; then
  mkdir -p "$HUB/.agents"
  ln -sfn "$HUB/.claude/skills" "$HUB/.agents/skills"
  ok "skills: assistants other than Claude Code can now read them too"
fi

say "Done"
cat <<EOF
This machine now shares one memory with the rest of them, at:

  $HUB/memory

What that means in practice: anything your assistant learns here is written into
your hub folder and travels with the next push, and anything it learned on
another machine is already here. Nothing is stored inside one AI tool any more.

There is one thing this cannot do for you: a memory only reaches the other
machines once it is pushed, so keep doing what you already do with the folder.
EOF
