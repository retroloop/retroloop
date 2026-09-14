#!/usr/bin/env bash
#
# Acceptance suite — the finish watch for one review (`scripts/watch-review.sh`).
#
#   bash tests/watch-review.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# THE DEFAULT IS NOW A WAIT WITH NO DEADLINE. A review takes as long as the
# human takes, and the watch that carries his press is a persistent monitor:
# the wait blocks until he presses Finish, prints one line, and exits. A
# `--timeout` slipped back into the armed command turns that into a watch that
# dies quietly after ten minutes — which is the exact failure the channel has
# already had four times. So the case this suite pins hardest is the argv the
# script execs: no `--timeout` unless one was asked for.
#
# `--print` is the dry run — the same argv, printed instead of exec'd — so the
# argv can be asserted with no app and no CLI anywhere. The exec cases prove
# `--print` is not lying: they run the real thing against a stub `retroloop`
# that records what it was called with.
#
# Every case runs under `env -i` in its own sandbox — a temp HOME, a temp PATH
# whose only interesting entry is that stub. No real CLI runs; the preflight
# aborts if one can be reached from the base PATH at all.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$REPO_ROOT/scripts/watch-review.sh"

BASE_PATH='/usr/bin:/bin'

# The wait the watch arms when nothing asked for a deadline — every flag of it,
# in order, and no `--timeout` among them.
WAIT_ARGV='review|wait|--follow|--retro|3|--json'
WAIT_ARGV_TIMED='review|wait|--follow|--retro|3|--timeout|30|--json'

# What `--print` puts on stdout: the resolved CLI, then exactly those arguments.
PRINT_TAIL='review wait --follow --retro 3 --json'
PRINT_TAIL_TIMED='review wait --follow --retro 3 --timeout 30 --json'

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SB_PATH=''
SANDBOXES=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl52w-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin" "$SB/nowhere"
  : >"$SB/retroloop.calls"
  cat >"$SB/event.json" <<'JSON'
{"kind":"ReviewFinished","retroId":3,"revision":1,"at":"2026-09-13T10:00:00.000Z","via":"stream"}
JSON
  SB_PATH="$SB/bin:$BASE_PATH"
  write_retroloop_stub
}

# The stub is the CLI's `review wait` and nothing else: it records the argv it
# was called with, prints the event, and exits 0 — the press, already landed.
write_retroloop_stub() {
  {
    printf '#!/bin/sh\n'
    printf "SB='%s'\n" "$SB"
    cat <<'STUB'
line=''; sep=''
for a in "$@"; do line="$line$sep$a"; sep='|'; done
printf '%s\n' "$line" >>"$SB/retroloop.calls"
cat "$SB/event.json"
exit 0
STUB
  } >"$SB/bin/retroloop"
  chmod +x "$SB/bin/retroloop"
}

cleanup() {
  local d
  for d in $SANDBOXES; do
    case "$d" in
      */rl52w-*) rm -rf "$d" ;;
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

expect_lacks() { # <what> <haystack> <needle>
  case "$2" in
    *"$3"*) miss "$1: [$2] still contains [$3]" ;;
  esac
}

# ── probes ───────────────────────────────────────────────────────────────────
OUT=''
ERR=''
RC=0

run_watch() { # <arg>...
  local errf="$SB/stderr.txt"
  OUT="$(env -i HOME="$SB/home" PATH="$SB_PATH" bash "$WATCH" "$@" 2>"$errf" </dev/null)"
  RC=$?
  ERR="$(cat "$errf" 2>/dev/null)"
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

# ── W1 · the dry run, with no deadline asked for ─────────────────────────────
begin W1 '--print with no --timeout — the argv carries no timeout flag'
new_sandbox
run_watch 3 --print
expect_eq 'exit' "$RC" '0'
expect_contains 'the printed argv' "$OUT" "$PRINT_TAIL"
expect_lacks 'no timeout flag' "$OUT" '--timeout'
end

# ── W2 · the dry run, with one ───────────────────────────────────────────────
begin W2 '--print --timeout 30 — the argv still carries it'
new_sandbox
run_watch 3 --print --timeout 30
expect_eq 'exit' "$RC" '0'
expect_contains 'the printed argv' "$OUT" "$PRINT_TAIL_TIMED"
end

# ── W3 · what it actually execs, with no deadline ────────────────────────────
begin W3 'arming with no --timeout — the exec argv carries no timeout flag'
new_sandbox
run_watch 3
expect_eq 'exit' "$RC" '0'
expect_eq 'the wait argv' "$(nth_call 1)" "$WAIT_ARGV"
expect_lacks 'no timeout flag' "$(nth_call 1)" '--timeout'
end

# ── W4 · what it execs when one was asked for ────────────────────────────────
begin W4 'arming with --timeout 30 — the exec argv carries it'
new_sandbox
run_watch 3 --timeout 30
expect_eq 'exit' "$RC" '0'
expect_eq 'the wait argv' "$(nth_call 1)" "$WAIT_ARGV_TIMED"
end

# ── W5 · one wait, one line ──────────────────────────────────────────────────
begin W5 'the press comes back on stdout — one line, and the process is the wait'
new_sandbox
run_watch 3
expect_eq 'lines on stdout' "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" '1'
expect_contains 'the event' "$OUT" '"kind":"ReviewFinished"'
expect_eq 'waits armed' "$(wc -l <"$SB/retroloop.calls" | tr -d ' ')" '1'
end

# ── W6 · the header tells the truth about what wakes a session ───────────────
begin W6 'the header: a printed line DOES wake a monitor, and the default has no deadline'
HEADER="$(sed -n '1,60p' "$WATCH" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g')"
if printf '%s' "$HEADER" | grep -qEi -- 'never .{0,30}(prints|printed|printing) a line'; then
  miss 'the header still claims a printed line never wakes a session'
fi
printf '%s' "$HEADER" | grep -qF -- 'every LINE the command prints to stdout' ||
  miss 'the header does not say a monitor wakes on every printed line'
printf '%s' "$HEADER" | grep -qEi -- 'persistent monitor' ||
  miss 'the header does not name the persistent monitor that arms this'
printf '%s' "$HEADER" | grep -qEi -- 'no --timeout' ||
  miss 'the header does not say what arming with no --timeout does'
printf '%s' "$HEADER" | grep -qEi -- 'blocks until' ||
  miss 'the header does not say the wait blocks until the press'
end

# ── W7 · usage and refusals still hold ───────────────────────────────────────
begin W7 'no CLI anywhere — arming refuses, and --print still answers'
new_sandbox
SB_PATH="$SB/nowhere:$BASE_PATH"
run_watch 3
expect_eq 'exit' "$RC" '2'
expect_eq 'stdout' "$OUT" ''
expect_contains 'stderr' "$ERR" 'watch-review: refusing —'
expect_contains 'stderr' "$ERR" 'no retroloop CLI'
expect_contains 'stderr points at setup' "$ERR" '/retroloop:setup'
run_watch 3 --print
expect_eq 'the dry run still exits 0' "$RC" '0'
expect_contains 'the dry run still prints the argv' "$OUT" "$PRINT_TAIL"
end

begin W8 'a bad retro id is refused before anything is armed'
new_sandbox
run_watch not-a-number
expect_eq 'exit' "$RC" '2'
expect_contains 'stderr' "$ERR" 'is not a retro id'
expect_eq 'nothing armed' "$(wc -l <"$SB/retroloop.calls" | tr -d ' ')" '0'
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=8
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
