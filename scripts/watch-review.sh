#!/usr/bin/env bash
#
# The finish watch — one exit-on-event wait.
#
# THE CHANNEL FAILED FOUR TIMES IN DEVELOPMENT, ONE HOP FURTHER ALONG EACH TIME:
#
#   1 · the press went unnoticed; the watcher was built. The hop fixed: nothing
#       was watching.
#   2 · the watcher polled and slept 20s, so a press sat in the database for
#       the length of the sleep. `review wait --follow` made it live. The hop
#       fixed: store → wait latency.
#   3 · the watcher SAW the press, printed `review finished: revision 1` to a
#       file, and told nobody. There are two ways to wake a session and they
#       listen for different things: a BACKGROUND TASK wakes its session when
#       the task EXITS, and a MONITOR WATCH (the Monitor tool, or a plugin
#       monitor) wakes it on every LINE the command prints to stdout. That
#       watcher wrote into a file, so it used neither. The hop fixed:
#       watcher → agent.
#   4 · the harness killed the watcher twice from outside and the watch was
#       stood down by hand. The hop that broke: watcher survival.
#
# This script is the shape that survived, CORRECT BY CONSTRUCTION: arming runs
# EXACTLY ONE wait and then `exec`s it, so the process you are watching IS the
# wait. There is no loop here to get wrong — after the exec there is no script
# left to loop — and one process covers BOTH ways of waking a session: its EXIT
# is the notification a background task delivers, and the ONE LINE it prints is
# the notification a monitor delivers. The end-to-end certification of this
# chain (red leg, full chain, killed-watcher drill) lives in the Retroloop app
# repository's test suite, where a throwaway stage and the finish-pressing test
# tool exist.
#
# WITH NO --timeout THE WAIT BLOCKS UNTIL THE PRESS, and that is the default,
# because a review takes as long as the human takes. It is the shape a
# PERSISTENT MONITOR arms: a Monitor watch with `persistent: true` and no
# deadline, running this script, which prints exactly one line when they press
# Finish and then exits — the line wakes the session once, and the exit ends the
# watch. Pass `--timeout <seconds>` only for the background-task fallback, where
# the harness caps how long a single task may run and the watch is re-armed on
# every exit. A deadline nobody asked for is a watch that dies quietly ten
# minutes in, which is how this channel broke before.
#
# scripts/watch-finish.sh is the OTHER watch — the resolve lane's manager,
# waiting on any review on the stage rather than on one. Neither is the other's
# fallback and neither replaces the other.
#
# NEVER STAND DOWN, RE-ARM ON KILL. While a review is open the watch is never
# voluntarily abandoned. A kill is not a stop gesture — it is a notification,
# which means re-arming costs one command and leaves no window: the wait reads
# from the store, so a press that lands while nothing is armed is still
# delivered to the next watch. The watch ends at review close, or on the
# human's explicit word to stop watching, and on nothing else.
#
# Usage:
#
#   watch-review.sh <retroId>
#       Arms one wait with NO deadline: it blocks until the human presses
#       Finish, prints the event JSON on one line, and exits 0. This is what a
#       persistent monitor runs.
#
#   watch-review.sh <retroId> --timeout <seconds>
#       The same wait with a deadline. Exit 0 = they pressed Finish, and the event
#       JSON is on stdout. Exit 7 = the seconds elapsed and nothing else;
#       re-arm. Any other exit is an error; re-arm and read the message.
#
#   watch-review.sh <retroId> --print
#       The dry run — print the exact command arming would exec, and stop. It
#       waits on nothing and needs no CLI.
#
#   watch-review.sh where | help

set -uo pipefail

say() { printf 'watch-review: %s\n' "$1" >&2; }
refuse() {
  printf 'watch-review: refusing — %s\n' "$1" >&2
  exit 2
}

usage() {
  cat >&2 <<'USAGE'
watch-review.sh — the finish watch.

Usage:
  watch-review.sh <retroId>                      arm one wait, no deadline
  watch-review.sh <retroId> --timeout <seconds>  arm one wait with a deadline
  watch-review.sh <retroId> --print              print what arming would exec
  watch-review.sh where                          what this resolves to
  watch-review.sh help                           this text

Arming runs exactly one `review wait --follow` and execs it: the process IS the
wait. Its one printed LINE is what wakes a monitor and its EXIT is what wakes a
background task, so one process covers both. Exit 0 with the event JSON on
stdout · exit 7 for the timeout, which means re-arm · anything else is an error,
which also means re-arm.

WITH NO --timeout THE WAIT BLOCKS UNTIL THE PRESS. That is the default and it is
what a persistent monitor arms. A deadline is for the background-task fallback,
where the harness caps a single task and the watch is re-armed on every exit.

A killed or exited watcher is RE-ARMED, never abandoned, for as long as the
review is open. A kill is a notification, not a stop gesture.

Environment — the shared resolver (scripts/resolve-cli.sh), first hit wins:
  1  retroloop on PATH
  2  RETROLOOP_APP      an app checkout directory, a .ts CLI entry, or an
                        executable; anything else falls through
     WATCH_REVIEW_CLI   the older spelling, still honored: a whole command
                        string, split on whitespace
  3  <root>/apps/retroloop, where <root> is $RETROLOOP_HOME, else ~/.retroloop
  4  this repo's apps/cli/src/bin.ts

Answers 2 to 4 are run by Bun, which the resolver finds itself — the shell's
own lookup, Bun's install folder, then the Homebrew and system folders — so
nothing has to be on PATH. RETROLOOP_BUN names the bun program outright, for a
Bun none of those places covers.

`where` prints what each of these is worth right now.
USAGE
  exit 2
}

if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  ROOT=''
fi

# ── what this runs ────────────────────────────────────────────────────────────
# One resolver for the whole plugin. This script and the SessionStart hook used
# to disagree about where the app is, which meant the hook could call an
# installed app "not set up" while the watch ran it happily.
RESOLVER="${BASH_SOURCE[0]%/*}/resolve-cli.sh"
[[ -f "$RESOLVER" ]] ||
  refuse "no resolver at $RESOLVER — this plugin checkout is incomplete."
# shellcheck source=resolve-cli.sh
. "$RESOLVER"

# The refusal a human actually reads when the watch will not start, and it has
# to name the right thing. The app installed with no Bun to run it is not a
# machine that needs setup run again; it is a machine where Bun is hiding from
# the kind of shell this script is.
require_cli() {
  retroloop_resolve_cli "$ROOT" && return 0
  if [[ "${RETROLOOP_CLI_MISS:-}" == 'no-bun' ]]; then
    refuse "Bun is missing — the app is at $(retroloop_root)/apps/retroloop and there is no Bun here to run it with. This watch looks for Bun itself, so nothing needs to be on PATH: install Bun, or set RETROLOOP_BUN to the bun program."
  fi
  refuse "no retroloop CLI — nothing on PATH, no usable RETROLOOP_APP, no checkout at $(retroloop_root)/apps/retroloop. Run /retroloop:setup, or set RETROLOOP_APP to the app checkout."
}

# ── the wait's own arguments ──────────────────────────────────────────────────
# An EMPTY timeout means no `--timeout` reaches the CLI at all, and the wait
# then blocks until the press. That is the default on purpose: a deadline
# nobody asked for is a watch that dies quietly while the review is still open.
WAIT_ARGV=()
build_wait_argv() {
  local retro="$1" timeout="$2"
  WAIT_ARGV=(review wait --follow --retro "$retro")
  [[ -n "$timeout" ]] && WAIT_ARGV+=(--timeout "$timeout")
  WAIT_ARGV+=(--json)
}

# ── arm ───────────────────────────────────────────────────────────────────────
arm() {
  local retro="$1" timeout="$2"

  require_cli
  build_wait_argv "$retro" "$timeout"

  # Everything the reader of the notification needs is printed BEFORE the wait
  # starts, because by the time the line or the exit arrives this script is
  # gone. The guidance has to already be in the output the notification carries.
  if [[ -n "$timeout" ]]; then
    say "armed on retro $retro — one wait, ${timeout}s; its LINE and its EXIT are both the notification."
    say "exit 7 = the timeout elapsed and NOTHING else. Re-arm; do not read it as a decline."
    say "relaunch:  watch-review.sh $retro --timeout $timeout"
  else
    say "armed on retro $retro — one wait, NO deadline; it blocks until Finish is pressed."
    say 'it prints exactly one line and exits: the line wakes a monitor, the exit wakes a background task.'
    say "relaunch:  watch-review.sh $retro"
  fi
  say 'hops: press → store → wait → watcher(this) → agent(the line, and the exit).'
  say 'exit 0 = the human pressed Finish; the event JSON is on stdout.'
  say 'any other exit = an error. Re-arm, and read the message.'
  say 'RE-ARM ON KILL: a killed watcher is re-armed immediately, never stood down.'

  # `exec`, and that is the whole design. The record this fixes is a monitor that
  # looped forever printing lines into a file nobody read; there is no loop that
  # can be written after this line, because there is no shell after this line.
  exec "${RETROLOOP_CLI[@]}" "${WAIT_ARGV[@]}"
}

# ── print ─────────────────────────────────────────────────────────────────────
# The dry run: exactly what arming would exec, on one line, waiting on nothing.
# It resolves the CLI when it can and says so when it cannot, so the argv can be
# read in an environment where no app is installed at all — and it tells the two
# misses apart like every other line here, because someone reading this is
# working out why a watch will not start and "no retroloop CLI" would send them
# to setup when the CLI is installed and Bun is what is hiding.
print_argv() {
  local retro="$1" timeout="$2"
  build_wait_argv "$retro" "$timeout"
  if retroloop_resolve_cli "$ROOT"; then
    printf '%s %s\n' "${RETROLOOP_CLI[*]}" "${WAIT_ARGV[*]}"
  elif [[ "${RETROLOOP_CLI_MISS:-}" == 'no-bun' ]]; then
    printf '<no retroloop CLI — Bun is missing> %s\n' "${WAIT_ARGV[*]}"
  else
    printf '<no retroloop CLI> %s\n' "${WAIT_ARGV[*]}"
  fi
  exit 0
}

# ── where ─────────────────────────────────────────────────────────────────────
# What this resolves to, and what every input is worth right now — so a watch
# that runs the wrong CLI, or none, is one command away from being explained.
where() {
  if retroloop_resolve_cli "$ROOT"; then
    printf 'cli:              %s  (%s)\n' "${RETROLOOP_CLI[*]}" "$RETROLOOP_CLI_SOURCE"
  elif [[ "${RETROLOOP_CLI_MISS:-}" == 'no-bun' ]]; then
    printf 'cli:              <none — Bun is missing; install Bun, or set RETROLOOP_BUN to the bun program>\n'
  else
    printf 'cli:              <none — put retroloop on PATH, set RETROLOOP_APP, or run /retroloop:setup>\n'
  fi

  if [[ -n "${RETROLOOP_APP:-}" ]]; then
    # Read off a command that is allowed to fail, the way the resolver itself
    # does it: a bare call whose answer is 1 or 2 is a failing command.
    local hint_rc=0
    retroloop_cli_from_hint "$RETROLOOP_APP" || hint_rc=$?
    case "$hint_rc" in
      0) printf 'RETROLOOP_APP:    %s  (%s)\n' "$RETROLOOP_APP" "${RETROLOOP_CLI[*]}" ;;
      2) printf 'RETROLOOP_APP:    %s  (an app checkout, and no Bun to run it)\n' "$RETROLOOP_APP" ;;
      *) printf 'RETROLOOP_APP:    [%s]  (set but unusable)\n' "$RETROLOOP_APP" ;;
    esac
  fi

  if [[ -n "${WATCH_REVIEW_CLI:-}" ]]; then
    if retroloop_cli_from_command "$WATCH_REVIEW_CLI"; then
      printf 'WATCH_REVIEW_CLI: %s  (alias)\n' "${RETROLOOP_CLI[*]}"
    else
      printf 'WATCH_REVIEW_CLI: [%s]  (alias; set but unusable)\n' "$WATCH_REVIEW_CLI"
    fi
  fi

  local app="$(retroloop_root)/apps/retroloop"
  if [[ -f "$app/apps/cli/src/bin.ts" ]]; then
    printf 'root install:     %s\n' "$app"
  else
    printf 'root install:     %s  (no checkout there)\n' "$app"
  fi

  printf 'repo root:        %s\n' "${ROOT:-<not a git worktree>}"
  exit 0
}

# ── dispatch ──────────────────────────────────────────────────────────────────
[[ $# -eq 0 ]] && usage
case "$1" in
  help | --help | -h) usage ;;
  where)
    [[ $# -eq 1 ]] || usage
    where
    ;;
esac

RETRO_ID="$1"
shift
[[ "$RETRO_ID" =~ ^[0-9]+$ ]] ||
  refuse "$RETRO_ID is not a retro id. The id is the number the review session announced — not the retrospective's ordinal, and not the session's."

# No deadline unless one is asked for.
TIMEOUT=''
PRINT_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      [[ $# -ge 2 ]] || usage
      TIMEOUT="$2"
      [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || refuse "--timeout takes whole seconds, not \"$TIMEOUT\"."
      shift 2
      ;;
    --print)
      PRINT_ONLY=1
      shift
      ;;
    *) usage ;;
  esac
done

[[ "$PRINT_ONLY" -eq 1 ]] && print_argv "$RETRO_ID" "$TIMEOUT"

arm "$RETRO_ID" "$TIMEOUT"
