#!/usr/bin/env bash
#
# Acceptance suite — the manager check (`scripts/ensure-manager.sh`).
#
#   bash tests/ensure-manager.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# ONE manager, EVER. The script's whole job is to leave exactly one manager
# session running for the personalization plugin, no matter how many times or
# how simultaneously it is called. That is what this suite pins: the lookup
# that recognizes a manager that is already up, the lock that stops two callers
# launching two of them, and the exact command line a launch and a resume are
# made of.
#
# NOTHING REAL RUNS. Every case runs under `env -i` in its own sandbox — a temp
# HOME, a temp RETROLOOP_HOME, and a temp PATH whose only interesting entry is
# a stub `claude`. The stub records every call, answers `agents --json` from
# rows the case seeded, and answers a launch by minting a row of its own one
# second later. A real `claude --bg` is never started, and the preflight aborts
# the suite if a real `claude` or `retroloop` can be reached from the base PATH
# at all.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENSURE="$REPO_ROOT/scripts/ensure-manager.sh"

BASE_PATH='/usr/bin:/bin'

SETUP_LINE='setup has not run; no manager'

# The launch line and the resume line, spelled out here so a change to either
# has to be made twice, on purpose, in two files.
LAUNCH_ARGV='--bg|--name|retroloop-manager|--agent|retroloop:manager|--permission-mode|auto|--model|fable|--settings|{"crossSessionInbound":"accept"}|start the resolve lane'
LAUNCH_ARGV_OPUS='--bg|--name|retroloop-manager|--agent|retroloop:manager|--permission-mode|auto|--model|opus|--settings|{"crossSessionInbound":"accept"}|start the resolve lane'
# A resume carries NO options besides the id and --bg: a background session
# restores its own saved options on an in-place resume, and any option passed
# starts a copy under a new id instead.
RESUME_ARGV='--resume|old-1111-2222-3333|--bg|resume the resolve lane'

MINTED='new-aaaa-bbbb-cccc'

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SB_PATH=''
SANDBOXES=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl50m-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin" "$SB/root" "$SB/nowhere"
  : >"$SB/rows.live"
  : >"$SB/rows.stopped"
  : >"$SB/claude.calls"
  printf '%s\n' "$MINTED" >"$SB/mint"
  SB_PATH="$SB/bin:$BASE_PATH"
  write_claude_stub
}

# The plugin is a directory at <root>/plugins/my — its presence is the whole
# "has setup run" test, so the cases that want a manager make one.
make_plugin() {
  mkdir -p "$SB/root/plugins/my"
}

# A row the stub will render as one session object.
seed_row() { # <live|stopped> <name> <cwd> <sessionId> <startedAt>
  printf '%s|%s|%s|%s\n' "$2" "$3" "$4" "$5" >>"$SB/rows.$1"
}

# The stub speaks the two `claude` surfaces this script uses and nothing else:
# `agents --json [--all]`, and a launch (anything else), which mints a live row
# one second later — the delay is the point, it is the window a second caller
# could launch into.
write_claude_stub() {
  {
    printf '#!/bin/sh\n'
    printf "SB='%s'\n" "$SB"
    cat <<'STUB'
line=''; sep=''
for a in "$@"; do line="$line$sep$a"; sep='|'; done
printf '%s\n' "$line" >>"$SB/claude.calls"

render() { # <rows file> — the rows as the JSON array `claude agents` prints
  first=1
  printf '[\n'
  while IFS='|' read -r n c s t; do
    [ -n "$n" ] || continue
    [ "$first" -eq 1 ] || printf ',\n'
    first=0
    printf ' {\n  "pid": 9996,\n  "id": "%.8s",\n  "cwd": "%s",\n  "kind": "background",\n  "startedAt": %s,\n  "sessionId": "%s",\n  "name": "%s",\n  "status": "busy",\n  "state": "working"\n }' "$s" "$c" "$t" "$s" "$n"
  done <"$1"
  printf '\n]\n'
}

case "$1" in
  agents)
    all=0
    for a in "$@"; do
      if [ "$a" = '--all' ]; then all=1; fi
    done
    if [ "$all" -eq 1 ]; then
      cat "$SB/rows.live" "$SB/rows.stopped" >"$SB/rows.both"
      render "$SB/rows.both"
    else
      render "$SB/rows.live"
    fi
    exit 0
    ;;
esac

# Anything else is a launch or a resume: record the environment and the working
# directory it was started from, then behave like `claude --bg` does — mint a
# session, print the backgrounded line, return immediately.
env >"$SB/launch.env"
pwd -P >"$SB/launch.cwd"
sleep 1
sid="$(cat "$SB/mint")"
printf 'retroloop-manager|%s|%s|1789295299000\n' "$(pwd -P)" "$sid" >>"$SB/rows.live"
printf 'backgrounded · %.8s · retroloop-manager\n' "$sid"
printf 'Run /bg to see background sessions.\n'
exit 0
STUB
  } >"$SB/bin/claude"
  chmod +x "$SB/bin/claude"
}

cleanup() {
  local d
  for d in $SANDBOXES; do
    case "$d" in
      */rl50m-*) rm -rf "$d" ;;
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

expect_not_contains() { # <what> <haystack> <needle>
  case "$2" in
    *"$3"*) miss "$1: [$2] must not contain [$3]" ;;
  esac
}

expect_no_lock() {
  [ ! -e "$SB/root/agents/manager/lock" ] ||
    miss "the lock at $SB/root/agents/manager/lock outlived the run"
}

# ── probes ───────────────────────────────────────────────────────────────────
OUT=''
ERR=''
RC=0

run_ensure() { # [VAR=VALUE ...]
  local errf="$SB/stderr.txt"
  OUT="$(env -i HOME="$SB/home" PATH="$SB_PATH" RETROLOOP_HOME="$SB/root" "$@" bash "$ENSURE" 2>"$errf" </dev/null)"
  RC=$?
  ERR="$(cat "$errf" 2>/dev/null)"
}

calls() { # every recorded argv line
  cat "$SB/claude.calls" 2>/dev/null
}

launch_line() { # the first launch or resume argv, as one `|`-joined line
  grep -F -e '--bg' "$SB/claude.calls" 2>/dev/null | head -n1
}

launch_count() {
  local n
  n="$(grep -c -F -e '--bg' "$SB/claude.calls" 2>/dev/null)"
  printf '%s' "${n:-0}" | tr -d ' \n'
}

# ── preflight ────────────────────────────────────────────────────────────────
preflight() {
  local stray
  for stray in retroloop claude; do
    local hit
    if hit="$(PATH="$BASE_PATH" command -v "$stray" 2>/dev/null)" && [ -n "$hit" ]; then
      printf 'ABORT: a real %s is on the base PATH (%s); the sandbox cannot isolate PATH.\n' "$stray" "$hit" >&2
      exit 2
    fi
  done
  [ -f "$ENSURE" ] || {
    printf 'ABORT: no script at %s\n' "$ENSURE" >&2
    exit 2
  }
}
preflight

# ── C1 · no plugin ───────────────────────────────────────────────────────────
begin C1 'no plugins/my — says setup has not run, launches nothing'
new_sandbox
run_ensure
expect_eq 'stdout' "$OUT" "$SETUP_LINE"
expect_eq 'exit' "$RC" '0'
expect_eq 'claude calls' "$(calls)" ''
end

# ── C2 · a manager is already up ─────────────────────────────────────────────
begin C2 'a live manager for this plugin — reports it, launches nothing'
new_sandbox
make_plugin
seed_row live retroloop-manager "$SB/root/plugins/my" 'up-1234-5678-9012' 1789295248826
run_ensure
expect_eq 'stdout' "$OUT" 'running up-1234-5678-9012'
expect_eq 'exit' "$RC" '0'
expect_eq 'launches' "$(launch_count)" '0'
expect_no_lock
end

# ── C3 · near misses are not the manager ─────────────────────────────────────
begin C3 'right name/wrong cwd and right cwd/wrong name — both ignored'
new_sandbox
make_plugin
seed_row live retroloop-manager "$SB/nowhere" 'elsewhere-0001' 1789295248826
seed_row live some-other-agent "$SB/root/plugins/my" 'notmine-0002' 1789295248827
run_ensure
expect_eq 'stdout' "$OUT" "running $MINTED"
expect_eq 'exit' "$RC" '0'
expect_eq 'launches' "$(launch_count)" '1'
end

# ── C4 · the launch ──────────────────────────────────────────────────────────
begin C4 'nothing live, nothing stopped — the manager launch line, verbatim'
new_sandbox
make_plugin
run_ensure
expect_eq 'stdout' "$OUT" "running $MINTED"
expect_eq 'exit' "$RC" '0'
expect_eq 'launch argv' "$(launch_line)" "$LAUNCH_ARGV"
expect_eq 'launched from' "$(cat "$SB/launch.cwd" 2>/dev/null)" "$(cd "$SB/root/plugins/my" && pwd -P)"
expect_contains 'the launch environment' "$(cat "$SB/launch.env" 2>/dev/null)" 'CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1'
expect_no_lock
end

# ── C5 · the model comes from the plugin's note ──────────────────────────────
begin C5 'model: opus in retroloop.md — the launch runs --model opus'
new_sandbox
make_plugin
cat >"$SB/root/plugins/my/retroloop.md" <<'NOTE'
model: opus
subagent model: opus
tracking: this tool only
NOTE
run_ensure
expect_eq 'launch argv' "$(launch_line)" "$LAUNCH_ARGV_OPUS"
expect_eq 'exit' "$RC" '0'
end

# ── C6 · the resume ──────────────────────────────────────────────────────────
begin C6 'a stopped manager — resumed by session id, not launched fresh'
new_sandbox
make_plugin
seed_row stopped retroloop-manager "$SB/root/plugins/my" 'older-0000-0000-0000' 1789295000000
seed_row stopped retroloop-manager "$SB/root/plugins/my" 'old-1111-2222-3333' 1789295248826
run_ensure
expect_eq 'resume argv' "$(launch_line)" "$RESUME_ARGV"
expect_not_contains 'the resume' "$(launch_line)" '--name'
expect_not_contains 'the resume' "$(launch_line)" '--agent'
expect_not_contains 'the resume' "$(launch_line)" '--settings'
expect_not_contains 'the resume' "$(launch_line)" '--model'
expect_not_contains 'the resume' "$(launch_line)" '--permission-mode'
expect_contains 'the resume environment' "$(cat "$SB/launch.env" 2>/dev/null)" 'CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1'
expect_eq 'exit' "$RC" '0'
end

# ── C7 · two callers at once ─────────────────────────────────────────────────
begin C7 'two invocations at the same moment — exactly one manager launched'
new_sandbox
make_plugin
(
  env -i HOME="$SB/home" PATH="$SB_PATH" RETROLOOP_HOME="$SB/root" bash "$ENSURE" >"$SB/a.out" 2>"$SB/a.err" </dev/null
  printf '%s\n' "$?" >"$SB/a.rc"
) &
(
  env -i HOME="$SB/home" PATH="$SB_PATH" RETROLOOP_HOME="$SB/root" bash "$ENSURE" >"$SB/b.out" 2>"$SB/b.err" </dev/null
  printf '%s\n' "$?" >"$SB/b.rc"
) &
wait
expect_eq 'launches' "$(launch_count)" '1'
expect_eq 'first stdout' "$(cat "$SB/a.out")" "running $MINTED"
expect_eq 'second stdout' "$(cat "$SB/b.out")" "running $MINTED"
expect_eq 'first exit' "$(cat "$SB/a.rc")" '0'
expect_eq 'second exit' "$(cat "$SB/b.rc")" '0'
expect_no_lock
end

# ── C8 · a stale lock ────────────────────────────────────────────────────────
begin C8 'a lock owned by a dead pid — removed, and the launch proceeds'
new_sandbox
make_plugin
mkdir -p "$SB/root/agents/manager/lock"
printf 'pid=999999\nstarted=2000-01-01T00:00:00Z\n' >"$SB/root/agents/manager/lock/owner"
run_ensure
expect_eq 'stdout' "$OUT" "running $MINTED"
expect_eq 'exit' "$RC" '0'
expect_eq 'launches' "$(launch_count)" '1'
expect_no_lock
end

# ── C9 · duplicates ──────────────────────────────────────────────────────────
begin C9 'two live managers — the earliest wins, and the duplicate is named'
new_sandbox
make_plugin
seed_row live retroloop-manager "$SB/root/plugins/my" 'late-2222' 1789295248900
seed_row live retroloop-manager "$SB/root/plugins/my" 'early-1111' 1789295248800
run_ensure
expect_eq 'stdout' "$OUT" 'running early-1111'
expect_eq 'exit' "$RC" '0'
expect_contains 'stderr' "$ERR" 'ensure-manager: warning — 2 managers running:'
expect_contains 'stderr names the early one' "$ERR" 'early-1111'
expect_contains 'stderr names the late one' "$ERR" 'late-2222'
expect_eq 'launches' "$(launch_count)" '0'
end

# ── C10 · no claude at all ───────────────────────────────────────────────────
begin C10 'no claude on PATH — says so and fails, leaving no lock'
new_sandbox
make_plugin
SB_PATH="$SB/nowhere:$BASE_PATH"
run_ensure
[ "$RC" -ne 0 ] || miss "exit: got 0, want non-zero"
expect_contains 'stderr' "$ERR" 'ensure-manager:'
expect_contains 'stderr names the missing command' "$ERR" 'claude'
expect_eq 'stdout' "$OUT" ''
expect_no_lock
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=10
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
