#!/usr/bin/env bash
# install-mac-linux.md, "On a Mac: start the notebook": does the notebook keep running after
# the terminal window it was started in is closed? A terminal window is a pseudo-terminal; here
# `script` makes one and runs the installer's start line in it, as Terminal does. Three ways a
# window ends are tried, each on a freshly started notebook:
#   A  the window is closed: its terminal goes away (the pseudo-terminal is hung up)
#   B  Terminal sends SIGHUP to the shell in the window, as it does when you close it
#   C  Ctrl+C in the window (SIGINT to what runs in the foreground)
# Before that: what a plain `kill` (SIGTERM) of the start process does.
#   bash .github/guide-verify/mac-terminal.sh "<the start line>"
set +e
line="$1"
health() { curl -s -m 3 http://127.0.0.1:47831/health >/dev/null; }
show() { ps -axo pid,ppid,pgid,tty,stat,command | grep -E 'start\.mjs|supervise\.mjs|server/main\.mjs' | grep -v grep | cut -c1-200; }
killall9() { pkill -9 -f 'integrated-runtime/start.mjs'; pkill -9 -f 'notebook/scripts/supervise.mjs'; pkill -9 -f 'notebook/server/main.mjs'; sleep 2; }
waitup() { for i in $(seq 1 60); do health && return 0; sleep 2; done; return 1; }
verdict() { sleep 10; if health; then echo "=> $1: the notebook STILL ANSWERS"; else echo "=> $1: nothing answers any more"; fi; show; }

echo '--- what runs now'; show
echo '--- a plain kill (SIGTERM) of the start process'
pkill -TERM -f 'integrated-runtime/start.mjs'; echo "pkill exit $?"
verdict 'after SIGTERM to start.mjs'
killall9; health && echo 'still answering after kill -9 (unexpected)' || echo 'all stopped (kill -9)'

for way in A B C; do
  echo; echo "--- way $way: started in a terminal window"
  script -q /dev/null bash -c "$line" > "evidence/terminal-$way.log" 2>&1 &
  term=$!
  waitup && echo 'it answers' || echo 'it did NOT start'
  show
  shellpid=$(pgrep -P "$term" | head -1)
  nodepgid=$(ps -o pgid= -p "$(pgrep -f 'integrated-runtime/start.mjs' | head -1)" 2>/dev/null | tr -d ' ')
  case $way in
    A) kill -9 "$term"; verdict 'A, the window closed (its terminal hung up)' ;;
    B) kill -HUP "$shellpid"; verdict "B, SIGHUP to the window's shell ($shellpid)" ;;
    C) kill -INT -- "-$nodepgid"; verdict "C, Ctrl+C (SIGINT to process group $nodepgid)" ;;
  esac
  kill -9 "$term" 2>/dev/null; killall9
done
