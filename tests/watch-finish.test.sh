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
# line, and that a wait which fails says WHY, out loud, every time — the exit
# code and the wait's own words — and then keeps listening. It used to pin the
# opposite: five failures and the watch stood down with a sentence naming the
# count. On the night that mattered the failures were an outside SIGTERM every
# few minutes, the lane lost its listener twice, and the sentence said "5".
# Standing down is now something the caller asks for, by number.
#
# Every case runs under `env -i` in its own sandbox — a temp HOME, a temp PATH
# whose interesting entries are a stub `retroloop` and a stub `sleep`. The CLI
# stub takes its exit codes from a plan file the case writes, one line per
# call, so a whole session of timeouts, presses and errors is scripted up front
# and replayed in order; the `sleep` stub records how long the watch meant to
# back off for and returns at once. No real CLI runs; the preflight aborts if
# one can be reached from the base PATH at all.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$REPO_ROOT/scripts/watch-finish.sh"

BASE_PATH='/usr/bin:/bin'

# The wait the watch arms — every flag of it, in order.
WAIT_ARGV='review|wait|--any|--follow|--timeout|600|--json'

# The event as the CLI prints it: pretty JSON over several lines. What the
# watch prints is that same event on ONE line, because a harness reads lines.
EVENT_ONE_LINE='{ "event": "review.finished", "retroId": 3, "revision": 1 }'

# A failed wait, as the watch reports it: the exit code, then the wait's own
# last words — or, when it left none, what the code itself says.
FAILED='watch-finish: wait failed'

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SB_PATH=''
SANDBOXES=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl50f-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin" "$SB/nowhere"
  : >"$SB/retroloop.calls"
  : >"$SB/sleep.calls"
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
  write_sleep_stub
}

# One plan line per call to the CLI:
#   <code>          exit with it; 0 prints the event first
#   <code>:<words>  the same, leaving <words> on stderr on the way out
#   term            die of a real SIGTERM, which is what an outside kill is
#   hang            never return
plan() { # <plan line>...
  local step
  : >"$SB/plan"
  for step in "$@"; do printf '%s\n' "$step" >>"$SB/plan"; done
}

# The back-off, without the waiting: what the watch asked `sleep` for is
# recorded, one call per line, and the stub returns at once.
write_sleep_stub() {
  {
    printf '#!/bin/sh\n'
    printf "SB='%s'\n" "$SB"
    cat <<'STUB'
printf '%s\n' "$*" >>"$SB/sleep.calls"
exit 0
STUB
  } >"$SB/bin/sleep"
  chmod +x "$SB/bin/sleep"
}

backoffs() { # every back-off the watch took, in order, on one line
  tr '\n' ' ' <"$SB/sleep.calls" | sed 's/ *$//'
}

# The stub is the CLI's `review wait` and nothing else: it records the call,
# reads the next line off the plan, and prints the event body when that line is
# 0. The looping watch no longer stops by itself, so PAST THE END OF THE PLAN
# THE STUB ENDS THE WATCH — a SIGTERM to its parent, by pid — and a watch that
# has lost the thread still cannot spin this suite forever. It then sleeps, in
# the same pid, so that the signal and not its own exit is what the watch hears.
#
# It also photographs the watch's PID file WHILE the wait is running — the only
# moment "the file exists while the watch runs" can be seen from — beside its
# own pid and its parent's, which are what the file has to name. The watch
# writes the wait's pid a moment after starting it, so the stub gives that line
# two seconds to land. A plan line of `hang` is a wait that never returns: the
# stub becomes a sleep, in the same pid, for a case that kills the watch.
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

pidfile="$SB/home/.retroloop/agents/manager/watch-finish.pid"
tries=0
while [ "$tries" -lt 20 ] && ! grep -q "^wait=$$\$" "$pidfile" 2>/dev/null; do
  /bin/sleep 0.1
  tries=$((tries + 1))
done
{
  printf 'stub=%s\nstub_parent=%s\n' "$$" "$PPID"
  cat "$pidfile" 2>/dev/null
} >"$SB/pidfile.seen.$n"

step="$(sed -n "${n}p" "$SB/plan")"
if [ -z "$step" ]; then
  kill -TERM "$PPID"
  exec /bin/sleep 5
fi
[ "$step" = 'hang' ] && exec /bin/sleep 30
[ "$step" = 'term' ] && kill -TERM $$
code="${step%%:*}"
case "$step" in
  *:*) printf '%s\n' "${step#*:}" >&2 ;;
esac
[ "$code" = '0' ] && cat "$SB/event.json"
exit "$code"
STUB
  } >"$SB/bin/retroloop"
  chmod +x "$SB/bin/retroloop"
}

# Processes a case started itself, by pid — the only things this suite ever
# signals. Whatever a failing case left running is put down here.
SPAWNED=''

cleanup() {
  local d p
  for p in $SPAWNED; do kill "$p" 2>/dev/null; done
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

# The watch's PID file, under the sandbox's own root — HOME is the sandbox's
# and RETROLOOP_HOME is unset, so the root is <home>/.retroloop.
pid_file() {
  printf '%s' "$SB/home/.retroloop/agents/manager/watch-finish.pid"
}

seen() { # <n> <key> — what the stub's nth call saw: stub, stub_parent, watch, owners, wait
  sed -n "s/^$2=//p" "$SB/pidfile.seen.$1" 2>/dev/null | head -n1
}

expect_number() { # <what> <value>
  case "$2" in
    '' | *[!0-9]*) miss "$1: got [$2], want a pid" ;;
  esac
}

expect_no_pid_file() {
  [ ! -e "$(pid_file)" ] || miss "the PID file at $(pid_file) outlived the watch: [$(tr '\n' ' ' <"$(pid_file)")]"
}

alive() { # <pid>
  case "${1:-}" in '' | *[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null
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
expect_eq 'stderr — a timeout is not a failure' "$ERR" ''
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

# ── D3 · the loop re-arms, and does not stand down ───────────────────────────
# Seven failures in a row — two more than used to end the watch — and it is
# still there for the press that follows them. What ends this run is the stub,
# past the end of its plan; the watch's own exit is the signal's, 143.
begin D3 'the loop re-arms through timeouts, presses and seven failures in a row — and is still listening'
new_sandbox
plan 7 0 7 0 1 1 1 1 1 1 1 0
run_watch
expect_eq 'lines: three presses, seven failures' "$LINES" '10'
expect_eq 'presses printed' "$(printf '%s\n' "$OUT" | grep -c -F -x -- "$EVENT_ONE_LINE")" '3'
expect_eq 'failures printed' "$(printf '%s\n' "$OUT" | grep -c -F -- "$FAILED")" '7'
expect_eq 'the press after the seventh failure is the last line' "$(printf '%s\n' "$OUT" | tail -n1)" "$EVENT_ONE_LINE"
case "$OUT" in
  *stopping*) miss "the watch stood down: [$OUT]" ;;
esac
expect_eq 'exit — ended by the stub, not by itself' "$RC" '143'
expect_eq 'waits armed' "$(wc -l <"$SB/retroloop.calls" | tr -d ' ')" '13'
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

# ── D6 · the PID file ────────────────────────────────────────────────────────
# The watch says who it is, in its own root: `ensure-manager.sh` reaps an
# orphaned watch by the pids in this file and by nothing else, so the file has
# to name the watch and the wait it is holding for exactly as long as they live.
begin D6 'the PID file names the watch and its wait while it runs, and is gone after — both forms'
new_sandbox
plan 7
run_watch --once
expect_eq '--once exit' "$RC" '7'
expect_number '--once: watch= while the wait ran' "$(seen 1 watch)"
expect_eq '--once: watch= is the watch itself' "$(seen 1 watch)" "$(seen 1 stub_parent)"
expect_eq '--once: wait= is the wait it started' "$(seen 1 wait)" "$(seen 1 stub)"
expect_number '--once: owners= names who armed it' "$(seen 1 owners | cut -d' ' -f1)"
expect_no_pid_file
new_sandbox
plan 7 0
run_watch
expect_eq 'loop: exit — ended by the stub, past its plan' "$RC" '143'
expect_eq 'loop: one watch through every wait' "$(seen 2 watch)" "$(seen 1 watch)"
expect_eq 'loop: watch= is the watch itself' "$(seen 2 watch)" "$(seen 2 stub_parent)"
expect_eq 'loop: wait= follows each new wait' "$(seen 2 wait)" "$(seen 2 stub)"
[ "$(seen 1 wait)" != "$(seen 2 wait)" ] || miss "loop: two waits shared one pid [$(seen 1 wait)]"
expect_no_pid_file
end

# ── D7 · a killed watch ──────────────────────────────────────────────────────
# The kill is this case's own: it signals, by pid, the watch it started.
begin D7 'a killed watch takes the wait it was holding with it, and leaves no PID file'
new_sandbox
plan hang
env -i HOME="$SB/home" PATH="$SB_PATH" bash "$WATCH" >"$SB/bg.out" 2>"$SB/bg.err" </dev/null &
WATCH_PID=$!
SPAWNED="$SPAWNED $WATCH_PID"
tries=0
while [ "$tries" -lt 50 ] && ! grep -q '^wait=[0-9]' "$(pid_file)" 2>/dev/null; do
  /bin/sleep 0.1
  tries=$((tries + 1))
done
HELD_WAIT="$(sed -n 's/^wait=//p' "$(pid_file)" 2>/dev/null | head -n1)"
SPAWNED="$SPAWNED $HELD_WAIT"
expect_eq 'watch= is the process this case started' "$(sed -n 's/^watch=//p' "$(pid_file)" 2>/dev/null | head -n1)" "$WATCH_PID"
alive "$HELD_WAIT" || miss "the wait [$HELD_WAIT] was not running before the kill"
kill "$WATCH_PID" 2>/dev/null
wait "$WATCH_PID" 2>/dev/null
expect_eq 'exit' "$?" '143'
tries=0
while [ "$tries" -lt 20 ] && alive "$HELD_WAIT"; do
  /bin/sleep 0.1
  tries=$((tries + 1))
done
alive "$HELD_WAIT" && miss "the wait [$HELD_WAIT] outlived its watch"
expect_no_pid_file
end

# ── D8 · nowhere to write the PID file ───────────────────────────────────────
begin D8 'a root it cannot write a PID file under — the watch still waits, and still prints the press'
new_sandbox
mkdir -p "$SB/home/.retroloop"
: >"$SB/home/.retroloop/agents"
plan 0
run_watch --once
expect_eq 'stdout' "$OUT" "$EVENT_ONE_LINE"
expect_eq 'exit' "$RC" '0'
end

# ── D9 · a failure says why ──────────────────────────────────────────────────
# On STDOUT, because under a Monitor a stdout line is the wake-up: a diagnosis
# on a stream nobody is woken by is the silence this watch exists to end.
begin D9 'the loop: every failed wait is one stdout line with its exit code and the wait'"'"'s own words'
new_sandbox
plan '9:the store is locked by another writer' term 1 0
run_watch
expect_eq 'lines: three failures, one press' "$LINES" '4'
expect_eq 'a failure that left words' "$(printf '%s\n' "$OUT" | sed -n 1p)" \
  "$FAILED (rc=9) the store is locked by another writer — still listening, next wait in 15s"
expect_eq 'a wait killed from outside' "$(printf '%s\n' "$OUT" | sed -n 2p)" \
  "$FAILED (rc=143) killed by SIGTERM — still listening, next wait in 30s"
expect_eq 'a failure that left nothing' "$(printf '%s\n' "$OUT" | sed -n 3p)" \
  "$FAILED (rc=1) no output — still listening, next wait in 60s"
expect_eq 'and the press still arrives' "$(printf '%s\n' "$OUT" | sed -n 4p)" "$EVENT_ONE_LINE"
expect_eq 'stderr stays clear of it' "$ERR" ''
end

# ── D10 · the back-off ───────────────────────────────────────────────────────
begin D10 'the back-off: 15 s doubling to a five-minute cap, and any wait that works resets it'
new_sandbox
plan 1 1 1 1 1 1 1 1
run_watch --max-failures 8
expect_eq 'eight failures, seven back-offs' "$(backoffs)" '15 30 60 120 240 300 300'
new_sandbox
plan 1 1 7 1 1 0 1 1 1
run_watch --max-failures 3
expect_eq 'a timeout and a press each reset it' "$(backoffs)" '15 30 15 30 15 30'
expect_eq 'lines: seven failures, one press' "$LINES" '8'
expect_eq 'exit' "$RC" '1'
end

# ── D11 · standing down, when asked to ───────────────────────────────────────
begin D11 '--max-failures <n>: n failed waits in a row and it stands down, saying so, exit 1'
new_sandbox
plan 1 '9:the store is locked' 1
run_watch --max-failures 3
expect_eq 'lines' "$LINES" '3'
expect_eq 'the last line says why, and that it is stopping' "$(printf '%s\n' "$OUT" | tail -n1)" \
  "$FAILED (rc=1) no output — 3 failures in a row (--max-failures 3), stopping"
expect_eq 'exit' "$RC" '1'
expect_eq 'waits armed' "$(wc -l <"$SB/retroloop.calls" | tr -d ' ')" '3'
expect_eq 'no back-off before an exit' "$(backoffs)" '15 30'
new_sandbox
plan 7
run_watch --max-failures several
expect_eq 'a word: exit' "$RC" '2'
expect_contains 'a word: stderr' "$ERR" 'watch-finish: refusing —'
expect_eq 'a word: nothing armed' "$(wc -l <"$SB/retroloop.calls" | tr -d ' ')" '0'
run_watch --max-failures
expect_eq 'no number: exit' "$RC" '2'
end

# ── D12 · one wait, failed ───────────────────────────────────────────────────
# On STDERR here: `--once` is for a background task, whose caller reads stdout
# as the event and finds stderr in the task's output file beside the exit code.
begin D12 '--once on a failure — the same line on stderr, stdout empty, the exit is the wait'"'"'s own'
new_sandbox
plan '9:the store is locked by another writer'
run_watch --once
expect_eq 'stdout' "$OUT" ''
expect_eq 'stderr' "$ERR" "$FAILED (rc=9) the store is locked by another writer"
expect_eq 'exit' "$RC" '9'
new_sandbox
plan term
run_watch --once
expect_eq 'killed: stdout' "$OUT" ''
expect_eq 'killed: stderr' "$ERR" "$FAILED (rc=143) killed by SIGTERM"
expect_eq 'killed: exit' "$RC" '143'
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=12
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
