#!/usr/bin/env bash
#
# The finish watch for ANY open review — the re-armed wait the resolve lane
# sits on.
#
#   watch-finish.sh [--timeout <seconds>] [--once] [--max-failures <n>]
#
# It waits for a human to press Finish on any retrospective, prints the event
# as ONE line, and waits again. It is the sibling of watch-review.sh, which
# waits on one named retro and exits; this one is the lane's standing watch and
# does not know in advance which retro the press will come from.
#
# TWO WAYS TO RUN IT, because harnesses wake on two different things:
#
#   Under a Monitor watch (the Monitor tool, or a plugin monitor) the session
#   is woken by every LINE the command prints. Run it with no flags: it loops
#   forever, printing one line per finished review, and each line is a wake-up.
#
#   Under a background task the session is woken only when the task EXITS.
#   Run it with `--once`: exactly one wait, whose exit is the notification —
#   exit 0 with the event on stdout, exit 7 for a plain timeout — and re-arm it
#   on every exit, timeouts included.
#
# SILENCE IS NEVER "STILL WAITING" — AND AN EXIT WITH NO REASON IS SILENCE TOO.
# A wait that keeps failing is not a wait; it is a dead channel that looks like
# patience. So a wait that fails says so at once, on a line of its own, with
# its exit code and the wait's own last words:
#
#   watch-finish: wait failed (rc=143) killed by SIGTERM — still listening, next wait in 15s
#
# In the looping form that line goes to STDOUT: a Monitor wakes its session on
# stdout lines, and a diagnosis nobody is woken by is no diagnosis. `--once`
# prints the same line on stderr, where a background task's output file keeps
# it and stdout stays the event's alone. Then the loop backs off — 15 seconds,
# doubling to a five-minute cap, back to 15 after any wait that works — and
# waits again. IT DOES NOT STAND DOWN. The wait reads the store, so re-entering
# loses nothing; and this watch used to count five anonymous failures and exit
# with a sentence naming the count, which on the night it mattered was an
# outside SIGTERM every few minutes, a lane that lost its listener twice, and
# nothing to diagnose it by. Every failure is heard now, from the first
# one, and the channel is still there afterwards.
#
# It stops by itself in two cases only: there is no CLI to run at all (exit 2,
# said on stderr), or it was armed with `--max-failures <n>` and that many
# waits in a row failed (exit 1, said on its last line).
#
# THE TIMEOUT IS A TICK, NOT A DEADLINE. `--timeout` (600 seconds unless given)
# bounds ONE call to the CLI, never the watch. In the looping form a timeout is
# the wait working — nothing is printed, and the next wait starts at once, for
# as long as the watch is armed. What the tick buys: a wedged call cannot hold
# the loop for ever, and a wait that somehow outlives its watch is gone within
# the tick.
#
# Exit codes: 0 a press (with the event), 7 a timeout, 2 no CLI to run, 1 the
# `--max-failures` stand-down; `--once` otherwise exits with the wait's own.

set -uo pipefail

DEFAULT_TIMEOUT=600
BACKOFF_FIRST=15
BACKOFF_CAP=300

refuse() {
  printf 'watch-finish: refusing — %s\n' "$1" >&2
  exit 2
}

usage() {
  cat >&2 <<'USAGE'
watch-finish.sh — the standing watch for any finished retrospective.

Usage:
  watch-finish.sh [--timeout <seconds>]   loop: one line per finished review
  watch-finish.sh --once [--timeout <s>]  one wait; its EXIT is the signal
  watch-finish.sh --max-failures <n>      loop, standing down after n failed
                                          waits in a row (default: never)
  watch-finish.sh where                   what this resolves to
  watch-finish.sh help                    this text

Looping is for a Monitor watch, which wakes a session on every stdout line.
`--once` is for a background task, which wakes a session only on the exit —
re-arm it every time it exits, timeouts included.

Exit 0 = someone pressed Finish, and the event JSON is on stdout, on one line.
Exit 7 = the timeout elapsed and nothing else; re-arm.

A wait that FAILS is a line of its own, with its exit code and its own words:
  watch-finish: wait failed (rc=<code>) <why>
on stdout in the loop, where it wakes whoever is listening, and on stderr
under `--once`. The loop then backs off (15 s, doubling to 5 min) and waits
again: that line is not a Finish, and the watch is still armed. It stands down
only when `--max-failures <n>` says so (exit 1), or when there is no CLI to
run at all (exit 2). `--timeout` bounds one call to the CLI, not the watch:
the loop re-enters on every timeout, silently, for as long as it is armed.

Environment — the shared resolver (scripts/resolve-cli.sh), first hit wins:
  1  retroloop on PATH
  2  RETROLOOP_APP      an app checkout directory, a .ts CLI entry, or an
                        executable; anything else falls through
     WATCH_REVIEW_CLI   the older spelling: a whole command string
  3  <root>/apps/retroloop, where <root> is $RETROLOOP_HOME, else ~/.retroloop
  4  this repo's apps/cli/src/bin.ts
USAGE
  exit 2
}

if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  ROOT=''
fi

# ── what this runs ───────────────────────────────────────────────────────────
# One resolver for the whole plugin: the hook, the review watch and this watch
# all get the same answer to "where is the app".
RESOLVER="${BASH_SOURCE[0]%/*}/resolve-cli.sh"
[ -f "$RESOLVER" ] ||
  refuse "no resolver at $RESOLVER — this plugin checkout is incomplete."
# shellcheck source=resolve-cli.sh
. "$RESOLVER"

require_cli() {
  retroloop_resolve_cli "$ROOT" ||
    refuse "no retroloop CLI — nothing on PATH, no usable RETROLOOP_APP, no checkout at $(retroloop_root)/apps/retroloop. Run /retroloop:setup, or set RETROLOOP_APP to the app checkout."
}

# ── one wait ─────────────────────────────────────────────────────────────────
# The event is printed on ONE line whatever shape the CLI prints it in, because
# a line is the unit a watching harness delivers. A pretty-printed event spread
# over six lines is six wake-ups carrying a fragment each.
EVENT=''

# The wait runs as a background job the watch then waits on, rather than inside
# a `$(…)`, for two reasons. The watch learns the wait's pid, which is what the
# PID file has to name. And a signal to the watch is acted on at once — bash
# sits on a trapped signal until a foreground command returns, and this one
# returns in ten minutes.
#
# BOTH STREAMS ARE KEPT. stdout is the event on a press; stderr is where the CLI
# says why it failed (`--json` errors are one line of JSON there). It used to
# go to /dev/null on the way in, so a failure had a code and no cause, and the
# loop did not keep the code either.
WAIT_PID=''
WAIT_TMP=''
WAIT_OUT=''
WAIT_ERR=''
WHY=''

one_wait() { # <timeout> → 0 pressed (EVENT set) · 7 timed out · other: failed (WHY set)
  local timeout="$1" rc
  "${RETROLOOP_CLI[@]}" review wait --any --follow --timeout "$timeout" --json >"$WAIT_OUT" 2>"$WAIT_ERR" &
  WAIT_PID=$!
  write_pid_file
  wait "$WAIT_PID"
  rc=$?
  WAIT_PID=''
  write_pid_file
  EVENT=''
  WHY=''
  case "$rc" in
    0) EVENT="$(one_line <"$WAIT_OUT")" ;;
    7) ;;
    *) WHY="$(why_it_failed "$rc")" ;;
  esac
  return "$rc"
}

one_line() { # stdin, whatever shape it is in → one line
  tr '\n\r\t' '   ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ *$//'
}

# The wait's own last words, from stderr: the last line that names an error,
# else the last line at all — a crash ends in a version banner, and the banner
# is not the cause. Nothing on stderr, then whatever it left on stdout. A code
# above 128 is a signal, and says so whatever else was said; a wait that was
# killed from outside usually says nothing at all, which is why the code is
# never dropped.
why_it_failed() { # <rc>
  local rc="$1" words='' signal=''
  words="$(grep -i 'error' "$WAIT_ERR" 2>/dev/null | tail -n1 | one_line)"
  [ -n "$words" ] || words="$(grep '[^[:space:]]' "$WAIT_ERR" 2>/dev/null | tail -n1 | one_line)"
  [ -n "$words" ] || words="$(one_line <"$WAIT_OUT")"
  words="$(printf '%s' "$words" | cut -c1-300)"
  if [ "$rc" -gt 128 ]; then
    signal="$(kill -l "$((rc - 128))" 2>/dev/null)"
  fi
  if [ -n "$signal" ]; then
    printf 'killed by SIG%s%s' "$signal" "${words:+: $words}"
  else
    printf '%s' "${words:-no output}"
  fi
}

# ── the PID file ─────────────────────────────────────────────────────────────
# THE WATCH SAYS WHO IT IS, IN ITS OWN ROOT. `ensure-manager.sh` clears away the
# watch a stopped manager left behind, and it used to find it by looking for
# the words `review wait --any` on any command line on the machine — which is
# also what the live lane's listener looks like, and a test sandbox's run of
# that script killed it on every run. So the watch writes down its own
# pid, the wait it is holding, and the two processes it answers to — the shell
# that armed it and that shell's parent, which under a Monitor is the session —
# in <root>/agents/manager/watch-finish.pid, and the reap reads that file and
# nothing else. A watch under another root writes another file.
#
# The file is written whole and moved into place, so it is never read half
# written; it is removed on every exit, signals included, and only by the watch
# it names — a later watch under the same root owns it from then on. A root the
# file cannot be written under is not a reason to refuse: an unreapable watch
# is a leak, and a watch that will not start is a deaf lane.
PID_FILE=''
OWNERS=''

owners_of() { # <pid> → "<parent> <grandparent>"
  local parent grand=''
  parent="$(ps -o ppid= -p "$1" 2>/dev/null | tr -d ' ')"
  [ -n "$parent" ] && grand="$(ps -o ppid= -p "$parent" 2>/dev/null | tr -d ' ')"
  printf '%s %s' "$parent" "$grand"
}

write_pid_file() {
  [ -n "$PID_FILE" ] || return 0
  printf 'watch=%s\nowners=%s\nwait=%s\n' "$$" "$OWNERS" "$WAIT_PID" >"$PID_FILE.$$" 2>/dev/null &&
    mv -f "$PID_FILE.$$" "$PID_FILE" 2>/dev/null
  return 0
}

start_pid_file() {
  local dir
  dir="$(retroloop_root)/agents/manager"
  mkdir -p "$dir" 2>/dev/null || return 0
  PID_FILE="$dir/watch-finish.pid"
  OWNERS="$(owners_of "$$")"
  write_pid_file
}

# Every way out comes through here: the wait is not left behind to be somebody
# else's orphan, and the file stops naming a watch that is gone.
on_exit() {
  [ -n "$WAIT_PID" ] && kill "$WAIT_PID" 2>/dev/null
  [ -n "$NAP_PID" ] && kill "$NAP_PID" 2>/dev/null
  case "$WAIT_TMP" in
    */watch-finish-*) rm -rf "$WAIT_TMP" ;;
  esac
  [ -n "$PID_FILE" ] || return 0
  rm -f "$PID_FILE.$$"
  if [ "$(sed -n 's/^watch=//p' "$PID_FILE" 2>/dev/null | head -n1)" = "$$" ]; then
    rm -f "$PID_FILE"
  fi
  return 0
}

# ── the back-off ─────────────────────────────────────────────────────────────
# A sleep the watch waits on, like the wait itself and for the same reason: a
# signal to the watch is heard now, not at the end of a five-minute nap.
NAP_PID=''

nap() { # <seconds>
  sleep "$1" &
  NAP_PID=$!
  wait "$NAP_PID"
  NAP_PID=''
}

# ── where ────────────────────────────────────────────────────────────────────
where() {
  if retroloop_resolve_cli "$ROOT"; then
    printf 'cli:              %s  (%s)\n' "${RETROLOOP_CLI[*]}" "$RETROLOOP_CLI_SOURCE"
  else
    printf 'cli:              <none — put retroloop on PATH, set RETROLOOP_APP, or run /retroloop:setup>\n'
  fi
  printf 'root install:     %s\n' "$(retroloop_root)/apps/retroloop"
  printf 'repo root:        %s\n' "${ROOT:-<not a git worktree>}"
  exit 0
}

# ── dispatch ─────────────────────────────────────────────────────────────────
ONCE=0
TIMEOUT="$DEFAULT_TIMEOUT"
MAX_FAILURES=0 # never: standing down is the caller's decision, by number

while [ $# -gt 0 ]; do
  case "$1" in
    help | --help | -h) usage ;;
    where)
      where
      ;;
    --once)
      ONCE=1
      shift
      ;;
    --timeout)
      [ $# -ge 2 ] || usage
      TIMEOUT="$2"
      case "$TIMEOUT" in
        '' | *[!0-9]*) refuse "--timeout takes whole seconds, not \"$TIMEOUT\"." ;;
      esac
      shift 2
      ;;
    --max-failures)
      [ $# -ge 2 ] || usage
      MAX_FAILURES="$2"
      case "$MAX_FAILURES" in
        '' | *[!0-9]*) refuse "--max-failures takes a whole number of failed waits in a row (0 is never), not \"$MAX_FAILURES\"." ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

require_cli

WAIT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/watch-finish-XXXXXX" 2>/dev/null)" ||
  refuse "could not make a temporary directory under ${TMPDIR:-/tmp} to read the wait's answer from."
WAIT_OUT="$WAIT_TMP/stdout"
WAIT_ERR="$WAIT_TMP/stderr"

trap on_exit EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
start_pid_file

# ── one wait, for a harness that wakes on an exit ────────────────────────────
if [ "$ONCE" -eq 1 ]; then
  one_wait "$TIMEOUT"
  rc=$?
  case "$rc" in
    0) printf '%s\n' "$EVENT" ;;
    7) ;;
    # The exit is the signal and stdout is the event's, so the cause goes to
    # stderr — which is where a background task's caller finds it, in the
    # task's output, beside the code.
    *) printf 'watch-finish: wait failed (rc=%s) %s\n' "$rc" "$WHY" >&2 ;;
  esac
  exit "$rc"
fi

# ── the loop, for a harness that wakes on a line ─────────────────────────────
failures=0
backoff="$BACKOFF_FIRST"
while :; do
  one_wait "$TIMEOUT"
  rc=$?
  case "$rc" in
    0)
      failures=0
      backoff="$BACKOFF_FIRST"
      printf '%s\n' "$EVENT"
      ;;
    7)
      # A timeout is the wait working: nothing happened, so nothing is said.
      failures=0
      backoff="$BACKOFF_FIRST"
      ;;
    *)
      # A failure is said, every time, on stdout — the line is the wake-up, and
      # it carries what the listener needs to tell a kill from a broken CLI.
      failures=$((failures + 1))
      if [ "$MAX_FAILURES" -gt 0 ] && [ "$failures" -ge "$MAX_FAILURES" ]; then
        printf 'watch-finish: wait failed (rc=%s) %s — %d failures in a row (--max-failures %d), stopping\n' \
          "$rc" "$WHY" "$failures" "$MAX_FAILURES"
        exit 1
      fi
      printf 'watch-finish: wait failed (rc=%s) %s — still listening, next wait in %ds\n' \
        "$rc" "$WHY" "$backoff"
      nap "$backoff"
      backoff=$((backoff * 2))
      [ "$backoff" -le "$BACKOFF_CAP" ] || backoff="$BACKOFF_CAP"
      ;;
  esac
done
