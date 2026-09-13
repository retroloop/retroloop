#!/usr/bin/env bash
#
# The finish watch for ANY open review — the re-armed wait the resolve lane
# sits on.
#
#   watch-finish.sh [--timeout <seconds>] [--once]
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
# SILENCE IS NEVER "STILL WAITING". A wait that keeps failing is not a wait; it
# is a dead channel that looks like patience. Five failures in a row and the
# looping form says so on stdout and exits non-zero, so whoever is listening
# hears the watch end rather than assuming it is still armed.
#
# Exit codes: 0 a press (with the event), 7 a timeout, 1 five failures in a
# row, 2 no CLI to run.

set -uo pipefail

DEFAULT_TIMEOUT=600
MAX_FAILURES=5

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
  watch-finish.sh where                   what this resolves to
  watch-finish.sh help                    this text

Looping is for a Monitor watch, which wakes a session on every stdout line.
`--once` is for a background task, which wakes a session only on the exit —
re-arm it every time it exits, timeouts included.

Exit 0 = someone pressed Finish, and the event JSON is on stdout, on one line.
Exit 7 = the timeout elapsed and nothing else; re-arm. Exit 1 = the wait failed
five times in a row and the watch stood down, said so, and stopped pretending.

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

one_wait() { # <timeout> → 0 pressed (EVENT set) · 7 timed out · other: failed
  local timeout="$1" out rc
  out="$("${RETROLOOP_CLI[@]}" review wait --any --follow --timeout "$timeout" --json 2>/dev/null)"
  rc=$?
  EVENT=''
  if [ "$rc" -eq 0 ]; then
    EVENT="$(printf '%s' "$out" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ *$//')"
  fi
  return "$rc"
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
    *) usage ;;
  esac
done

require_cli

# ── one wait, for a harness that wakes on an exit ────────────────────────────
if [ "$ONCE" -eq 1 ]; then
  one_wait "$TIMEOUT"
  rc=$?
  [ "$rc" -eq 0 ] && printf '%s\n' "$EVENT"
  exit "$rc"
fi

# ── the loop, for a harness that wakes on a line ─────────────────────────────
failures=0
while :; do
  one_wait "$TIMEOUT"
  rc=$?
  case "$rc" in
    0)
      failures=0
      printf '%s\n' "$EVENT"
      ;;
    7)
      # A timeout is the wait working: nothing happened, so nothing is said.
      failures=0
      ;;
    *)
      failures=$((failures + 1))
      if [ "$failures" -ge "$MAX_FAILURES" ]; then
        printf 'watch-finish: review wait failed %d times; stopping\n' "$MAX_FAILURES"
        exit 1
      fi
      ;;
  esac
done
