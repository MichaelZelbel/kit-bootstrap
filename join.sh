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

HUB="${1:-${HUB:-$HOME/hub}}"
HUB="$(cd "$HUB" 2>/dev/null && pwd)" || die "There is no folder at ${1:-${HUB:-$HOME/hub}}.
Clone your hub there first, then run this again. If your hub is somewhere else,
pass the path: bash join.sh /path/to/your/hub"

say "Joining this machine to the hub at $HUB"

# 1. Get the latest of everything, because a join that leaves you on last month's
#    memory looks exactly like a join that worked.
if [ -d "$HUB/.git" ]; then
  if git -C "$HUB" pull --rebase --autostash -q origin "$(git -C "$HUB" rev-parse --abbrev-ref HEAD)" 2>/dev/null; then
    ok "pulled the latest version of your hub"
  else
    warn "could not pull (no network, or a conflict to sort out by hand).
     Continuing with the copy already on this machine, which may be out of date."
  fi
else
  warn "$HUB is not a git folder, so there is nothing to pull. Continuing."
fi

# 2. The shared memory. This is the whole point of joining.
kb_link_ai_memory "$HUB"

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
