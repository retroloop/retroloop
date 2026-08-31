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
#            `review finished: revision 1` to a file, and told nobody: an agent
#            harness re-invokes an agent when a background task EXITS, never
#            when it prints a line. The hop fixed: watcher → agent.
#   retro 13 `r-fourth-finish-channel-failure` — the harness killed the watcher
#            twice from outside and the watch was stood down by hand. The hop
#            that broke: watcher survival.
#
# This script is the shape that survived, CORRECT BY CONSTRUCTION: arming runs
# EXACTLY ONE wait and then `exec`s it, so the process you are watching IS the
# wait and its EXIT is the notification — the one signal every harness in use
# delivers. There is no loop here to get wrong: after the exec there is no
# script left to loop. The end-to-end certification of this chain (red leg,
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

Environment:
  WATCH_REVIEW_CLI   the retroloop CLI to run (default: an app checkout at
                     ~/Developer/retroloop-app, the current repo's, then PATH)
USAGE
  exit 2
}

if ! ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  ROOT=''
fi

# ── what this runs ────────────────────────────────────────────────────────────
declare -a CLI=()
resolve_cli() {
  if [[ -n "${WATCH_REVIEW_CLI:-}" ]]; then
    read -r -a CLI <<<"$WATCH_REVIEW_CLI"
    # An override that is all whitespace resolves to no command at all, and
    # running "${CLI[@]}" empty would arm nothing quietly — which is the failure
    # mode this whole script exists to remove.
    [[ ${#CLI[@]} -gt 0 ]] || return 1
    return 0
  fi
  if [[ -f "$HOME/Developer/retroloop-app/apps/cli/src/bin.ts" ]]; then
    CLI=(bun "$HOME/Developer/retroloop-app/apps/cli/src/bin.ts")
    return 0
  fi
  if [[ -n "$ROOT" && -f "$ROOT/apps/cli/src/bin.ts" ]]; then
    CLI=(bun "$ROOT/apps/cli/src/bin.ts")
    return 0
  fi
  local found
  if found="$(command -v retroloop 2>/dev/null)"; then
    CLI=("$found")
    return 0
  fi
  return 1
}

require_cli() {
  resolve_cli ||
    refuse "no retroloop CLI — no app checkout found and none on PATH. Run /retroloop:setup, or set WATCH_REVIEW_CLI."
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
  exec "${CLI[@]}" review wait --follow --retro "$retro" --timeout "$timeout" --json
}

# ── where ─────────────────────────────────────────────────────────────────────
where() {
  if resolve_cli; then
    printf 'cli:         %s\n' "${CLI[*]}"
  else
    printf 'cli:         <none — set WATCH_REVIEW_CLI or run /retroloop:setup>\n'
  fi
  printf 'repo root:   %s\n' "${ROOT:-<not a git worktree>}"
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
