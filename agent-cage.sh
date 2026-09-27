#!/usr/bin/env bash
# =============================================================================
# kit-bootstrap / agent-cage.sh
#
# Keeps an AI agent from taking a Linux server down by accident.
#
# WHY: on 2026-09-21 an AI agent sent this over SSH while debugging:
#     D=$(dirname $(readlink -f $(which hermes))); grep -rln repair-attempts $D/.. ...
# `which hermes` found nothing, so $D was empty and `$D/..` became `/..`: the whole
# filesystem, including /proc, which has no end. The agent's tool gave up after two
# minutes and closed the connection, but closing an SSH connection does not stop what it
# started. The grep held a CPU core for 5.4 days until the hosting company throttled the
# server. Agents will write commands like that again; rules telling them not to do not
# hold. So the SERVER draws the line, for every command an agent runs:
#
#   agent-cage      runs one command in its own cage: at most one CPU core (--cpu), and
#                   ended, with everything it started, after a maximum time (--max, default
#                   1h), whoever is still waiting
#   agent.slice     where every cage lives: all of them together get at most three quarters
#                   of the machine, and the real services win when the CPU is contended
#   agent-cage-ssh  forced command for an agent's SSH key: every remote command goes
#                   through agent-cage. Interactive logins and file copies are untouched.
#   agent-cage-shell  a SHELL= for a crontab whose every job is agent work: each job then
#                   runs through agent-cage (limit AGENT_CAGE_MAX, default 2h)
#   agent-cage-watch  every 10 minutes: stops busy leftovers of closed SSH sessions and
#                   busy children of watched agent services (a process over REAP_PCT of a
#                   core for longer than REAP_MIN_AGE), and warns when the whole machine
#                   stays busy for an hour.
#
# Anything meant to outlive the cage is started deliberately with `systemd-run`.
# The cage protects against accidents, not against an agent that sets out to remove it:
# an agent with root can uninstall anything. It needs systemd (every mainstream VPS image).
#
# Usage (as root):
#   agent-cage.sh install [--notify CMD]    install or refresh; safe to run again
#   agent-cage.sh cage-key FILE MATCH [--max 8h]  route the key(s) in authorized_keys FILE
#                                           whose line contains MATCH through the cage
#                                           (a command's time limit: 1h unless --max)
#   agent-cage.sh watch-unit GLOB           also watch the children of these services
#                                           (e.g. 'hermes-gateway*.service')
#   agent-cage.sh check                     is every piece in place (exit 1 if not)
#   agent-cage.sh selftest                  replay a runaway command, prove it is stopped
#   agent-cage.sh uninstall
#
# Products that install agents on a server: copy this file into the package (pin a tag
# and its SHA-256), run `install`, `cage-key` for each agent key you add, `watch-unit` for
# each agent service, and put `agent-cage --max <time> --` in front of every scheduled
# agent run. Test with `selftest`.
# =============================================================================
set -u

AGENT_CAGE_VERSION="1.0.0"
CONF_DIR=/etc/agent-cage
CONF="$CONF_DIR/config"
BIN=/usr/local/bin/agent-cage
SSH_BIN=/usr/local/sbin/agent-cage-ssh
SHELL_BIN=/usr/local/sbin/agent-cage-shell
WATCH_BIN=/usr/local/sbin/agent-cage-watch
SLICE=/etc/systemd/system/agent.slice
UNIT_DIR=/etc/systemd/system

_say() { printf '[agent-cage] %s\n' "$*"; }
_die() { printf '[agent-cage] stop: %s\n' "$*" >&2; exit 1; }
_need_root() { [ "$(id -u)" -eq 0 ] || _die "run as root"; }
_need_systemd() { [ -d /run/systemd/system ] || _die "this machine does not run systemd"; }

# --- config ------------------------------------------------------------------
_conf_get() { # key default
  local v
  v=$(sed -n "s/^$1=\"\{0,1\}\([^\"]*\)\"\{0,1\}$/\1/p" "$CONF" 2>/dev/null | tail -1)
  printf '%s' "${v:-$2}"
}
_conf_set() { # key value
  mkdir -p "$CONF_DIR"; touch "$CONF"
  local tmp; tmp=$(mktemp)
  grep -v "^$1=" "$CONF" >"$tmp" || true
  printf '%s="%s"\n' "$1" "$2" >>"$tmp"
  cat "$tmp" >"$CONF"; rm -f "$tmp"
}

# --- the pieces --------------------------------------------------------------
_write_slice() {
  local ncpu quota
  ncpu=$(nproc 2>/dev/null || echo 1)
  quota=$(( ncpu * 75 ))
  cat >"$SLICE" <<EOF
# Installed by agent-cage.sh $AGENT_CAGE_VERSION (kit-bootstrap). Every command an AI agent
# runs on this machine lands here. Each one is capped on its own (agent-cage --cpu, one core
# by default); this is only the net under all of them together: three quarters of the CPU
# ($ncpu cores), a lower share than the services when the CPU is contended, and memory is
# reclaimed from them first.
#
# Not half the machine, and not the only cap: on 2026-09-27 a single runaway in a slice
# capped at one core (of two) starved every other agent job in it and cron piled up.
[Unit]
Description=Commands run by AI agents (agent-cage)
Before=slices.target

[Slice]
CPUQuota=${quota}%
CPUWeight=50
MemoryHigh=50%
MemoryMax=75%
TasksMax=4096
EOF
}

_write_cage() {
  cat >"$BIN" <<'EOF'
#!/bin/bash
# agent-cage: run a command the way every AI agent's command on this server runs: in its
# own cage in agent.slice, at most --cpu of the processor (default 100% = one core) and
# ended, with everything it started, after --max (default 1h), even when nobody is waiting.
#   agent-cage [--max 1h] [--cpu 100%] [--] command [args...]
#   agent-cage [--max 1h] [--cpu 100%] -c 'shell command'
# Installed by kit-bootstrap/agent-cage.sh. Something meant to outlive the cage is started
# deliberately with systemd-run.
set -u
max="${AGENT_CAGE_MAX:-1h}"
cpu="${AGENT_CAGE_CPU:-100%}"
while [ $# -gt 0 ]; do
  case "$1" in
    --max) max="${2:?--max needs a time, e.g. 30m}"; shift 2 ;;
    --max=*) max="${1#--max=}"; shift ;;
    --cpu) cpu="${2:?--cpu needs a share, e.g. 50%}"; shift 2 ;;
    --cpu=*) cpu="${1#--cpu=}"; shift ;;
    -c) set -- /bin/bash -c "${2:?-c needs a command}"; break ;;
    --) shift; break ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "usage: agent-cage [--max 1h] [--] command..." >&2; exit 2; }
# Already caged (an agent inside the cage calling it again): keep the first clock, so a caged
# command cannot buy itself more time. AGENT_CAGE_NEW=1 (the selftest) asks for a fresh cage.
case "$(cat /proc/self/cgroup 2>/dev/null)" in
  *"/agent.slice/"*) [ "${AGENT_CAGE_NEW:-}" = 1 ] || exec "$@" ;;
esac
if [ "$(id -u)" -eq 0 ] && [ -d /run/systemd/system ]; then
  exec systemd-run --quiet --scope --collect --slice=agent.slice \
    --unit="agent-$(date +%s)-$$-$RANDOM" -p RuntimeMaxSec="$max" -p CPUQuota="$cpu" -- "$@"
fi
# A normal user cannot join the system slice. The time limit still holds: timeout ends the
# command's whole process group, and nice keeps it behind the real services.
exec timeout --kill-after=30s "$max" nice -n 10 "$@"
EOF
  chmod 755 "$BIN"
}

_write_ssh() {
  cat >"$SSH_BIN" <<'EOF'
#!/bin/sh
# agent-cage-ssh: forced command for an AI agent's SSH key (authorized_keys command=...).
# A remote command runs through agent-cage, so it ends even after the agent has hung up.
# An interactive login and a file copy (sftp) behave exactly as without it.
# Installed by kit-bootstrap/agent-cage.sh.
cmd="${SSH_ORIGINAL_COMMAND:-}"
shell="${SHELL:-/bin/bash}"
case "$cmd" in
  "") exec "$shell" -l ;;
  sftp|internal-sftp|*/sftp-server|*/sftp-server\ *)
    for s in /usr/lib/openssh/sftp-server /usr/libexec/openssh/sftp-server /usr/lib/ssh/sftp-server; do
      [ -x "$s" ] && exec "$s"
    done
    echo "agent-cage-ssh: no sftp-server found" >&2; exit 1 ;;
esac
exec /usr/local/bin/agent-cage --max "${AGENT_CAGE_SSH_MAX:-1h}" -- "$shell" -c "$cmd"
EOF
  chmod 755 "$SSH_BIN"
}

_write_shell() {
  cat >"$SHELL_BIN" <<'EOF'
#!/bin/sh
# agent-cage-shell: put SHELL=/usr/local/sbin/agent-cage-shell at the top of a crontab whose
# every job is agent work, and each job runs through agent-cage. Cron calls $SHELL -c "job".
# The time limit is AGENT_CAGE_MAX (a crontab line of its own), 2h when unset.
# Installed by kit-bootstrap/agent-cage.sh.
exec /usr/local/bin/agent-cage --max "${AGENT_CAGE_MAX:-2h}" -- /bin/sh "$@"
EOF
  chmod 755 "$SHELL_BIN"
}

_write_watch() {
  cat >"$WATCH_BIN" <<'EOF'
#!/bin/bash
# agent-cage-watch: the net under the cage. Runs every 10 minutes (agent-cage-watch.timer).
# 1. Stops a BUSY process (over REAP_PCT of one core since the last run, older than
#    REAP_MIN_AGE) that is a leftover of a closed login session, or a child of a watched
#    agent service (WATCH_UNITS; the service's own main process is never touched).
#    Idle leftovers cost nothing and may be wanted, so they stay.
# 2. Warns through NOTIFY_CMD when the whole machine stays above WARN_PCT for WARN_RUNS
#    runs in a row, naming the three busiest processes. At most once a day.
# Silence is normal. Log: /var/log/agent-cage.log. Config: /etc/agent-cage/config.
# Installed by kit-bootstrap/agent-cage.sh.
set -u
REAP_PCT=50; REAP_MIN_AGE=3600; WARN_PCT=80; WARN_RUNS=6; WATCH_UNITS=""; NOTIFY_CMD=""
[ -r /etc/agent-cage/config ] && . /etc/agent-cage/config
DRY="${DRY_RUN:-0}"
DIR=/var/lib/agent-cage; LOG=/var/log/agent-cage.log
mkdir -p "$DIR"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
HZ=$(getconf CLK_TCK); t_now=$(date +%s)
up=$(cut -d' ' -f1 /proc/uptime | cut -d. -f1)

prev="$DIR/ticks.prev"; cur="$DIR/ticks.cur"; : >"$cur"
t_prev=$(cat "$DIR/ticks.time" 2>/dev/null || echo 0)
dt=$(( t_now - t_prev )); [ "$dt" -gt 0 ] || dt=1

# consider WHY CGROUP_DIR [skip-oldest]
consider() {
  local why=$1 procs="$2/cgroup.procs" skip=${3:-} pids pid st ticks start age old pct cmd oldest=""
  pids=$(cat "$procs" 2>/dev/null) || return 0
  if [ -n "$skip" ]; then # the service's main process is its oldest
    oldest=$(for p in $pids; do s=$(cat /proc/$p/stat 2>/dev/null) || continue; set -- ${s##*) }; echo "${20} $p"; done | sort -n | head -1 | cut -d' ' -f2)
  fi
  for pid in $pids; do
    [ "$pid" = "$oldest" ] && continue
    st=$(cat "/proc/$pid/stat" 2>/dev/null) || continue
    set -- ${st##*) }   # $1 is field 3 of stat: utime=$12 stime=$13 starttime=$20
    ticks=$(( ${12} + ${13} )); start=${20}
    echo "$pid $start $ticks" >>"$cur"
    age=$(( up - start / HZ ))
    [ "$age" -ge "$REAP_MIN_AGE" ] || continue
    old=$(awk -v p="$pid" -v s="$start" '$1==p && $2==s {print $3}' "$prev" 2>/dev/null)
    [ -n "$old" ] && [ "$t_prev" -gt 0 ] || continue
    pct=$(( (ticks - old) * 100 / HZ / dt ))
    [ "$pct" -ge "$REAP_PCT" ] || continue
    cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | cut -c1-200)
    echo "$(now) stop pid=$pid why=$why age=${age}s cpu=${pct}% cmd=$cmd dry=$DRY" >>"$LOG"
    [ "$DRY" = 1 ] && continue
    kill -TERM "$pid" 2>/dev/null; sleep 5; kill -KILL "$pid" 2>/dev/null
  done
}

# 1a. leftovers of closed login sessions
if command -v loginctl >/dev/null 2>&1; then
  for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
    [ "$(loginctl show-session "$s" -p State --value 2>/dev/null)" = closing ] || continue
    uid=$(loginctl show-session "$s" -p User --value 2>/dev/null)
    consider "closed-session-$s" "/sys/fs/cgroup/user.slice/user-$uid.slice/session-$s.scope"
  done
fi
# 1b. children of watched agent services
for g in $WATCH_UNITS; do
  for d in /sys/fs/cgroup/system.slice/$g /sys/fs/cgroup/user.slice/user-*.slice/user@*.service/*/$g; do
    [ -d "$d" ] || continue
    for sub in $(find "$d" -type d); do consider "${d##*/}" "$sub" skip; done
  done
done
mv "$cur" "$prev"; echo "$t_now" >"$DIR/ticks.time"

# 2. warn when the whole machine stays busy
read -r _ u n s i w q sq st _ </proc/stat
busy=$((u + n + s + q + sq + st)); total=$((busy + i + w))
read -r pb pt 2>/dev/null <"$DIR/stat.prev" || { pb=0; pt=0; }
echo "$busy $total" >"$DIR/stat.prev"
[ "$pt" -gt 0 ] && [ "$total" -gt "$pt" ] || exit 0
load=$(( (busy - pb) * 100 / (total - pt) ))
echo "$(now) cpu=${load}% of $(nproc) cores" >>"$LOG"
if [ "$load" -lt "$WARN_PCT" ]; then echo 0 >"$DIR/streak"; exit 0; fi
streak=$(( $(cat "$DIR/streak" 2>/dev/null || echo 0) + 1 )); echo "$streak" >"$DIR/streak"
[ "$streak" -ge "$WARN_RUNS" ] || exit 0
today=$(date -u +%F)
[ "$(cat "$DIR/warned" 2>/dev/null)" = "$today" ] && exit 0
# A Hermes gateway's command line is a python bootstrap; name it by its profile instead.
top=$(ps -eo pcpu,etimes,user,args --sort=-pcpu --no-headers | awk '$4 != "ps"' | head -3 \
      | sed -E "s#^( *[0-9.]+ +[0-9]+ +[a-z0-9_-]+ ).*'-p', '([^']+)'.*#\1hermes-\2#; s#^( *[0-9.]+ +[0-9]+ +[a-z0-9_-]+ ).*'gateway', 'run'.*#\1hermes-default#" \
      | awk '{c=$4; for(i=5;i<=NF&&i<8;i++) c=c" "$i; printf "%s (%s%%, user %s, running %dh); ", c, $1, $3, $2/3600}')
msg="This server has been above ${WARN_PCT}% CPU for $(( WARN_RUNS * 10 )) minutes. Hosting companies throttle a server that stays like this. Busiest: ${top%; }."
[ "$DRY" = 1 ] && { echo "$(now) would warn: $msg" >>"$LOG"; exit 0; }
logger -t agent-cage "$msg" 2>/dev/null
if [ -n "$NOTIFY_CMD" ]; then $NOTIFY_CMD "$msg" >>"$LOG" 2>&1 || { echo "$(now) notify failed" >>"$LOG"; exit 0; }; fi
echo "$today" >"$DIR/warned"; echo "$(now) warned (${load}%)" >>"$LOG"
EOF
  chmod 755 "$WATCH_BIN"
  cat >"$UNIT_DIR/agent-cage-watch.service" <<EOF
[Unit]
Description=agent-cage: stop runaway agent leftovers, warn on sustained CPU
[Service]
Type=oneshot
ExecStart=$WATCH_BIN
EOF
  cat >"$UNIT_DIR/agent-cage-watch.timer" <<'EOF'
[Unit]
Description=agent-cage watch every 10 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
AccuracySec=30s
[Install]
WantedBy=timers.target
EOF
}

# --- commands ----------------------------------------------------------------
cmd_install() {
  _need_root; _need_systemd
  local notify=""
  while [ $# -gt 0 ]; do
    case "$1" in --notify) notify="$2"; shift 2 ;; *) _die "unknown option $1" ;; esac
  done
  mkdir -p "$CONF_DIR"; touch "$CONF"
  [ -n "$notify" ] && _conf_set NOTIFY_CMD "$notify"
  grep -q '^WATCH_UNITS=' "$CONF" || _conf_set WATCH_UNITS ""
  _write_slice; _write_cage; _write_ssh; _write_shell; _write_watch
  echo "$AGENT_CAGE_VERSION" >"$CONF_DIR/version"
  systemctl daemon-reload
  systemctl start agent.slice 2>/dev/null || true
  systemctl enable --now agent-cage-watch.timer >/dev/null 2>&1 || _die "could not start agent-cage-watch.timer"
  _say "installed $AGENT_CAGE_VERSION: agent.slice (net $(sed -n 's/^CPUQuota=//p' "$SLICE") CPU, one core per command), agent-cage, agent-cage-ssh, agent-cage-shell, agent-cage-watch (every 10 min)"
}

cmd_cage_key() {
  _need_root
  local file="${1:-}" match="${2:-}" max="${4:-}" n=0 tmp fc="$SSH_BIN"
  [ "${3:-}" = --max ] && [ -n "$max" ] && fc="AGENT_CAGE_SSH_MAX=$max $SSH_BIN"
  [ -f "$file" ] && [ -n "$match" ] || _die "usage: cage-key AUTHORIZED_KEYS_FILE MATCH [--max 8h]"
  [ -x "$SSH_BIN" ] || _die "run install first"
  grep -F -- "$match" "$file" >/dev/null || _die "no key in $file matches '$match'"
  cp -p "$file" "$file.bak-agent-cage-$(date +%Y%m%d%H%M%S)"
  tmp=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"$match"*)
        case "$line" in
          *agent-cage-ssh*) : ;;
          *'command="'*) _say "left alone, it already has its own command=: ${line:0:60}..." ;;
          ssh-*|ecdsa-*|sk-*) line="command=\"$fc\" $line"; n=$((n + 1)) ;;
          *) line="command=\"$fc\",$line"; n=$((n + 1)) ;;
        esac ;;
    esac
    printf '%s\n' "$line"
  done <"$file" >"$tmp"
  cat "$tmp" >"$file"; rm -f "$tmp"
  _say "caged $n key(s) matching '$match' in $file"
}

cmd_watch_unit() {
  _need_root
  local g="${1:-}" cur
  [ -n "$g" ] || _die "usage: watch-unit GLOB"
  cur=$(_conf_get WATCH_UNITS "")
  case " $cur " in *" $g "*) _say "already watched: $g"; return 0 ;; esac
  _conf_set WATCH_UNITS "$(echo "$cur $g" | sed 's/^ *//')"
  _say "watching children of $g"
}

cmd_check() {
  local bad=0
  _c() { if eval "$2"; then printf '  ok    %s\n' "$1"; else printf '  FAIL  %s\n' "$1"; bad=1; fi; }
  _c "agent.slice defined with a CPU net" "grep -q '^CPUQuota=' '$SLICE' 2>/dev/null"
  _c "agent-cage installed" "[ -x '$BIN' ]"
  _c "agent-cage-ssh installed" "[ -x '$SSH_BIN' ]"
  _c "agent-cage-shell installed" "[ -x '$SHELL_BIN' ]"
  _c "agent-cage-watch timer active" "systemctl is-active --quiet agent-cage-watch.timer"
  _c "watch ran in the last 20 minutes" "[ -n \"\$(find /var/lib/agent-cage/ticks.time -mmin -20 2>/dev/null)\" ]"
  return $bad
}

cmd_selftest() {
  _need_root; _need_systemd
  local bad=0 t0 t1 left u1 u2 pct quota ncpu scope cpumax out
  _r() { if [ "$2" = 0 ]; then printf '  PASS  %s\n' "$1"; else printf '  FAIL  %s\n' "$1"; bad=1; fi; }
  cmd_check >/dev/null || { cmd_check; _die "not fully installed"; }
  # Each test needs its own cage with its own short clock, also when the selftest itself was
  # started from inside one (over a caged SSH key, from a caged crontab).
  export AGENT_CAGE_NEW=1

  # Wait up to $2 seconds for no process matching $1 to be left.
  _gone() { local i=0; while pgrep -f "$1" >/dev/null && [ $i -lt "$2" ]; do sleep 1; i=$((i + 1)); done; ! pgrep -f "$1" >/dev/null; }

  # 1. The command of 2026-09-21, verbatim in shape: an empty variable turns a search into
  #    a search of the whole filesystem. The cage must end it at its time limit.
  t0=$(date +%s)
  ( "$BIN" --max 5s -- bash -c 'D=$(dirname "$(readlink -f "$(command -v no-such-program-agent-cage)")" 2>/dev/null); D=${D#.}; grep -rln agent-cage-needle-$RANDOM "$D/.." >/dev/null 2>&1' ) >/dev/null 2>&1
  t1=$(date +%s)
  _gone agent-cage-needle 10; left=$?
  _r "the 2026-09-21 whole-disk search is stopped at its limit (after $((t1 - t0))s)" "$([ $((t1 - t0)) -le 20 ] && [ "$left" -eq 0 ]; echo $?)"

  # 2. A leftover: the command returns at once, the busy child it left behind must still die.
  ( "$BIN" --max 4s --cpu 10% -- bash -c 'nohup sh -c "while :; do :; done # agent-cage-orphan" >/dev/null 2>&1 & exit 0' ) >/dev/null 2>&1
  i=0; until pgrep -f agent-cage-orphan >/dev/null || [ $i -ge 3 ]; do sleep 1; i=$((i + 1)); done
  pgrep -f agent-cage-orphan >/dev/null; _r "a leftover is still running before the limit" "$?"
  _gone agent-cage-orphan 20; _r "the leftover is gone after the limit" "$?"

  # 3. The CPU cap of one command: busy loops on every core, capped at 20%, for 4 seconds.
  #    Short and small on purpose: this runs on live servers.
  ncpu=$(nproc)
  ( "$BIN" --max 4s --cpu 20% -- bash -c "for i in \$(seq $ncpu); do (while :; do :; done # agent-cage-burn
    ) & done; wait" ) >/dev/null 2>&1 &
  sleep 1
  scope=$(grep -l agent-cage-burn /proc/[0-9]*/cmdline 2>/dev/null | head -1 | cut -d/ -f3)
  scope=$(sed -n 's#^0::##p' "/proc/$scope/cgroup" 2>/dev/null)
  u1=$(sed -n 's/^usage_usec //p' "/sys/fs/cgroup$scope/cpu.stat" 2>/dev/null); sleep 2
  u2=$(sed -n 's/^usage_usec //p' "/sys/fs/cgroup$scope/cpu.stat" 2>/dev/null)
  wait 2>/dev/null
  pct=$(( (${u2:-0} - ${u1:-0}) / 20000 ))
  _r "one command stays under its own cap (${pct}% of a core, cap 20%)" "$([ -n "$u1" ] && [ "$pct" -le 25 ]; echo $?)"
  _gone agent-cage-burn 10; _r "and is gone after its limit" "$?"
  quota=$(sed -n 's/^CPUQuota=\([0-9]*\)%//p' "$SLICE")
  cpumax=$(cat /sys/fs/cgroup/agent.slice/cpu.max 2>/dev/null)
  _r "the kernel enforces the net under all of them (agent.slice cpu.max: $cpumax, ${quota}%)" "$(set -- $cpumax; [ "${1:-max}" != max ] && [ $(( $1 * 100 / $2 )) -eq "$quota" ]; echo $?)"

  # 4. An agent's SSH command lands in the cage; a nested agent-cage keeps the first clock.
  out=$(SSH_ORIGINAL_COMMAND='cat /proc/self/cgroup' SHELL=/bin/bash "$SSH_BIN" 2>&1)
  _r "an SSH command from a caged key runs inside agent.slice" "$(case "$out" in *agent.slice*) echo 0 ;; *) echo 1 ;; esac)"
  out=$(SSH_ORIGINAL_COMMAND='exit 7' SHELL=/bin/bash "$SSH_BIN" >/dev/null 2>&1; echo $?)
  _r "its exit code comes back unchanged ($out)" "$([ "$out" = 7 ]; echo $?)"

  out=$(AGENT_CAGE_MAX=30s "$SHELL_BIN" -c 'cat /proc/self/cgroup' 2>&1)
  _r "a cron job run through agent-cage-shell lands in agent.slice" "$(case "$out" in *agent.slice*) echo 0 ;; *) echo 1 ;; esac)"

  [ "$bad" = 0 ] && _say "selftest passed" || _say "selftest FAILED"
  return $bad
}

cmd_uninstall() {
  _need_root
  systemctl disable --now agent-cage-watch.timer >/dev/null 2>&1
  rm -f "$UNIT_DIR/agent-cage-watch.service" "$UNIT_DIR/agent-cage-watch.timer" "$WATCH_BIN"
  local f
  for f in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    [ -f "$f" ] && grep -q agent-cage-ssh "$f" && sed -i -E "s#command=\"(AGENT_CAGE_SSH_MAX=[^ ]+ )?$SSH_BIN\"(,| )##" "$f"
  done
  local u
  for u in $(cut -d: -f1 /etc/passwd); do
    crontab -u "$u" -l 2>/dev/null | grep -q "^SHELL=$SHELL_BIN" || continue
    crontab -u "$u" -l | grep -v "^SHELL=$SHELL_BIN" | crontab -u "$u" -
  done
  rm -f "$SSH_BIN" "$SHELL_BIN" "$BIN" "$SLICE"
  systemctl daemon-reload
  _say "removed (config kept in $CONF_DIR)"
}

case "${1:-}" in
  install) shift; cmd_install "$@" ;;
  cage-key) shift; cmd_cage_key "$@" ;;
  watch-unit) shift; cmd_watch_unit "$@" ;;
  check) cmd_check ;;
  selftest) cmd_selftest ;;
  uninstall) cmd_uninstall ;;
  version) echo "$AGENT_CAGE_VERSION" ;;
  *) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
