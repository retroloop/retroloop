#!/usr/bin/env bash
#
# Acceptance suite — the finish watch for any retrospective
# (`scripts/watch-finish.sh`).
#
#   bash tests/watch-finish.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# SILENCE MUST NEVER MEAN "STILL WAITING". The watch waits on a review that no
# one is looking at; if it dies quietly, the human presses Finish and nothing
# happens, for as long as it takes someone to notice. So the two things this
# suite pins hardest are that a finished review always produces exactly one
# line, and that a wait which keeps failing gives up OUT LOUD instead of
# looping forever on nothing.
#
# Every case runs under `env -i` in its own sandbox — a temp HOME, a temp PATH
# whose only interesting entry is a stub `retroloop`. The stub takes its exit
# codes from a plan file the case writes, one line per call, so a whole session
# of timeouts, presses and errors is scripted up front and replayed in order.
# No real CLI runs; the preflight aborts if one can be reached from the base
# PATH at all.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$REPO_ROOT/scripts/watch-finish.sh"

BASE_PATH='/usr/bin:/bin'

# The wait the watch arms — every flag of it, in order.
WAIT_ARGV='review|wait|--any|--follow|--timeout|600|--json'

# The event as the CLI prints it: pretty JSON over several lines. What the
# watch prints is that same event on ONE line, because a harness reads lines.
EVENT_ONE_LINE='{ "event": "review.finished", "retroId": 3, "revision": 1 }'

STOPPING='watch-finish: review wait failed 5 times; stopping'

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SB_PATH=''
SANDBOXES=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl50f-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin" "$SB/nowhere"
  : >"$SB/retroloop.calls"
  : >"$SB/plan"
  cat >"$SB/event.json" <<'JSON'
{
 "event": "review.finished",
 "retroId": 3,
 "revision": 1
}
JSON
  SB_PATH="$SB/bin:$BASE_PATH"
  write_retroloop_stub
}

plan() { # <exit code>...
  local code
  : >"$SB/plan"
  for code in "$@"; do printf '%s\n' "$code" >>"$SB/plan"; done
}

# The stub is the CLI's `review wait` and nothing else: it records the call,
# reads the next exit code off the plan, and prints the event body when that
# code is 0. Past the end of the plan it fails, so a watch that has lost the
# thread still stops rather than spinning this suite forever.
write_retroloop_stub() {
  {
    printf '#!/bin/sh\n'
    printf "SB='%s'\n" "$SB"
    cat <<'STUB'
line=''; sep=''
for a in "$@"; do line="$line$sep$a"; sep='|'; done
printf '%s\n' "$line" >>"$SB/retroloop.calls"

n="$(cat "$SB/n" 2>/dev/null)"
[ -n "$n" ] || n=0
n=$((n + 1))
printf '%s\n' "$n" >"$SB/n"

code="$(sed -n "${n}p" "$SB/plan")"
[ -n "$code" ] || code=1
[ "$code" = '0' ] && cat "$SB/event.json"
exit "$code"
STUB
  } >"$SB/bin/retroloop"
  chmod +x "$SB/bin/retroloop"
}

cleanup() {
  local d
  for d in $SANDBOXES; do
    case "$d" in
      */rl50f-*) rm -rf "$d" ;;
    esac
  done
}
trap cleanup EXIT

# ── the ledger ───────────────────────────────────────────────────────────────
CASE=''
CASE_DESC=''
CASE_FAILED=0
DETAIL=''
FAILED_IDS=''

begin() {
  CASE="$1"
  CASE_DESC="$2"
  CASE_FAILED=0
  DETAIL=''
}

miss() {
  CASE_FAILED=1
  DETAIL="$DETAIL     $1"$'\n'
}

end() {
  if [ "$CASE_FAILED" -eq 0 ]; then
    printf 'PASS %s — %s\n' "$CASE" "$CASE_DESC"
  else
    printf 'FAIL %s — %s\n' "$CASE" "$CASE_DESC"
    printf '%s' "$DETAIL"
    FAILED_IDS="$FAILED_IDS $CASE"
  fi
}

expect_eq() { # <what> <actual> <expected>
  [ "$2" = "$3" ] || miss "$1: got [$2] want [$3]"
}

expect_contains() { # <what> <haystack> <needle>
  case "$2" in
    *"$3"*) ;;
    *) miss "$1: [$2] does not contain [$3]" ;;
  esac
}

# ── probes ───────────────────────────────────────────────────────────────────
OUT=''
ERR=''
RC=0
LINES=0

run_watch() { # <arg>...
  local errf="$SB/stderr.txt"
  OUT="$(env -i HOME="$SB/home" PATH="$SB_PATH" bash "$WATCH" "$@" 2>"$errf" </dev/null)"
  RC=$?
  ERR="$(cat "$errf" 2>/dev/null)"
  if [ -z "$OUT" ]; then
    LINES=0
  else
    LINES="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  fi
}

nth_call() { # <n>
  sed -n "$1p" "$SB/retroloop.calls" 2>/dev/null
}

# ── preflight ────────────────────────────────────────────────────────────────
preflight() {
  local name hit
  for name in retroloop claude; do
    if hit="$(PATH="$BASE_PATH" command -v "$name" 2>/dev/null)" && [ -n "$hit" ]; then
      printf 'ABORT: a real %s is on the base PATH (%s); the sandbox cannot isolate PATH.\n' "$name" "$hit" >&2
      exit 2
    fi
  done
  [ -f "$WATCH" ] || {
    printf 'ABORT: no script at %s\n' "$WATCH" >&2
    exit 2
  }
}
preflight

# ── D1 · one wait, timed out ─────────────────────────────────────────────────
begin D1 '--once on a timeout — silent, and exit 7 means re-arm'
new_sandbox
plan 7
run_watch --once
expect_eq 'stdout' "$OUT" ''
expect_eq 'exit' "$RC" '7'
end

# ── D2 · one wait, pressed ───────────────────────────────────────────────────
begin D2 '--once on a press — the event on exactly one line, exit 0'
new_sandbox
plan 0
run_watch --once
expect_eq 'lines' "$LINES" '1'
expect_eq 'stdout' "$OUT" "$EVENT_ONE_LINE"
expect_eq 'exit' "$RC" '0'
end

# ── D3 · the loop re-arms, and gives up out loud ─────────────────────────────
begin D3 'the loop re-arms through timeouts and presses, then stops after five failures'
new_sandbox
plan 7 0 7 0 1 1 1 1 1
run_watch
expect_eq 'lines' "$LINES" '3'
expect_eq 'stdout' "$OUT" "$(printf '%s\n%s\n%s' "$EVENT_ONE_LINE" "$EVENT_ONE_LINE" "$STOPPING")"
expect_eq 'exit' "$RC" '1'
expect_eq 'waits armed' "$(wc -l <"$SB/retroloop.calls" | tr -d ' ')" '9'
end

# ── D4 · the wait it arms ────────────────────────────────────────────────────
begin D4 'the wait is `review wait --any --follow --timeout 600 --json`'
new_sandbox
plan 7
run_watch --once
expect_eq 'the wait argv' "$(nth_call 1)" "$WAIT_ARGV"
new_sandbox
plan 7
run_watch --once --timeout 30
expect_eq 'the timeout is honored' "$(nth_call 1)" 'review|wait|--any|--follow|--timeout|30|--json'
end

# ── D5 · no CLI ──────────────────────────────────────────────────────────────
begin D5 'no retroloop anywhere — it refuses instead of waiting on nothing'
new_sandbox
SB_PATH="$SB/nowhere:$BASE_PATH"
run_watch --once
expect_eq 'exit' "$RC" '2'
expect_eq 'stdout' "$OUT" ''
expect_contains 'stderr' "$ERR" 'watch-finish: refusing —'
expect_contains 'stderr' "$ERR" 'no retroloop CLI'
expect_contains 'stderr points at setup' "$ERR" '/retroloop:setup'
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=5
n_failed=0
for _ in $FAILED_IDS; do n_failed=$((n_failed + 1)); done
n_passed=$((total - n_failed))

printf '\n%d cases: %d passed, %d failed' "$total" "$n_passed" "$n_failed"
if [ -n "$FAILED_IDS" ]; then
  printf ' —%s\n' "$FAILED_IDS"
  exit 1
fi
printf '\n'
exit 0
