#!/usr/bin/env bash
#
# The finish watch — one exit-on-event wait (retro-12 `r-monitor-notify-gap`;
# retro-13 `r-fourth-finish-channel-failure`). Provenance citations of the form
# `retro N r-…` resolve only in the authoring repository; the rules they mark
# are stated in full here.
#
# THE CHANNEL FAILED FOUR TIMES IN DEVELOPMENT, ONE HOP FURTHER ALONG EACH TIME:
#
#   retro 7  `r-finish-event-unnoticed`  — the press went unnoticed; the watcher
#            was built. The hop fixed: nothing was watching.
#   retro 9  `r-monitor-not-realtime`    — the watcher polled and slept 20s, so
#            a press sat in the database for the length of the sleep. `review
#            wait --follow` made it live. The hop fixed: store → wait latency.
#   retro 12 `r-monitor-notify-gap`      — the watcher SAW the press, printed
#            `review finished: revision 1` to a file, and told nobody. There
#            are two ways to wake a session and they listen for different
#            things: a BACKGROUND TASK wakes its session when the task EXITS,
#            and a MONITOR WATCH (the Monitor tool, or a plugin monitor) wakes
#            it on every LINE the command prints to stdout. That watcher wrote
#            into a file, so it used neither. The hop fixed: watcher → agent.
#   retro 13 `r-fourth-finish-channel-failure` — the harness killed the watcher
#            twice from outside and the watch was stood down by hand. The hop
#            that broke: watcher survival.
#
# This script is the shape that survived, CORRECT BY CONSTRUCTION: arming runs
# EXACTLY ONE wait and then `exec`s it, so the process you are watching IS the
# wait and its EXIT is the notification — the signal the background-task path
# delivers. There is no loop here to get wrong: after the exec there is no
# script left to loop. A session that watches through a Monitor instead wants
# the other shape, a loop whose every printed line is a wake-up; that is
# scripts/watch-finish.sh. The end-to-end certification of this chain (red leg,
# full chain, killed-watcher drill) lives in the Retroloop app repository's
# test suite, where a throwaway stage and the finish-pressing test tool exist.
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
#   watch-review.sh <retroId> [--timeout <seconds>]
#       Arms one wait. Exit 0 = the human pressed Finish, and the event JSON is
#       on stdout. Exit 7 = the timeout elapsed and nothing else; re-arm. Any
#       other exit is an error; re-arm and read the message.
#
#   watch-review.sh where | help

set -uo pipefail

DEFAULT_TIMEOUT=600

say() { printf 'watch-review: %s\n' "$1" >&2; }
refuse() {
  printf 'watch-review: refusing — %s\n' "$1" >&2
  exit 2
}

usage() {
  cat >&2 <<'USAGE'
watch-review.sh — the finish watch.

Usage:
  watch-review.sh <retroId> [--timeout <seconds>]   arm one wait
  watch-review.sh where                             what this resolves to
  watch-review.sh help                              this text

Arming runs exactly one `review wait --follow` and execs it: the process IS the
wait, and its EXIT is the notification. Exit 0 with the event JSON on stdout ·
exit 7 for the timeout, which means re-arm · anything else is an error, which
also means re-arm.

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

require_cli() {
  retroloop_resolve_cli "$ROOT" ||
    refuse "no retroloop CLI — nothing on PATH, no usable RETROLOOP_APP, no checkout at $(retroloop_root)/apps/retroloop. Run /retroloop:setup, or set RETROLOOP_APP to the app checkout."
}

# ── arm ───────────────────────────────────────────────────────────────────────
arm() {
  local retro="$1" timeout="$2"

  require_cli

  # Everything the reader of the exit notification needs is printed BEFORE the
  # wait starts, because by the time the exit arrives this script is gone. The
  # guidance has to already be in the output the notification carries.
  say "armed on retro $retro — one wait, ${timeout}s, and its EXIT is the notification."
  say 'hops: press → store → wait → watcher(this) → agent(the exit notification).'
  say 'exit 0 = the human pressed Finish; the event JSON is on stdout.'
  say "exit 7 = the timeout elapsed and NOTHING else. Re-arm; do not read it as a decline."
  say 'any other exit = an error. Re-arm, and read the message.'
  say 'RE-ARM ON KILL: a killed watcher is re-armed immediately, never stood down.'
  say "relaunch:  watch-review.sh $retro --timeout $timeout"

  # `exec`, and that is the whole design. The record this fixes is a monitor that
  # looped forever printing lines into a file nobody read; there is no loop that
  # can be written after this line, because there is no shell after this line.
  exec "${RETROLOOP_CLI[@]}" review wait --follow --retro "$retro" --timeout "$timeout" --json
}

# ── where ─────────────────────────────────────────────────────────────────────
# What this resolves to, and what every input is worth right now — so a watch
# that runs the wrong CLI, or none, is one command away from being explained.
where() {
  if retroloop_resolve_cli "$ROOT"; then
    printf 'cli:              %s  (%s)\n' "${RETROLOOP_CLI[*]}" "$RETROLOOP_CLI_SOURCE"
  else
    printf 'cli:              <none — put retroloop on PATH, set RETROLOOP_APP, or run /retroloop:setup>\n'
  fi

  if [[ -n "${RETROLOOP_APP:-}" ]]; then
    if retroloop_cli_from_hint "$RETROLOOP_APP"; then
      printf 'RETROLOOP_APP:    %s  (%s)\n' "$RETROLOOP_APP" "${RETROLOOP_CLI[*]}"
    else
      printf 'RETROLOOP_APP:    [%s]  (set but unusable)\n' "$RETROLOOP_APP"
    fi
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

TIMEOUT="$DEFAULT_TIMEOUT"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      [[ $# -ge 2 ]] || usage
      TIMEOUT="$2"
      [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || refuse "--timeout takes whole seconds, not \"$TIMEOUT\"."
      shift 2
      ;;
    *) usage ;;
  esac
done

arm "$RETRO_ID" "$TIMEOUT"
