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
#
# AND NOTHING ON THIS MACHINE IS SIGNALLED BY NAME. The base PATH is /usr/bin:/bin,
# which is where the real `pkill`, `pgrep` and `killall` live — so an `env -i`
# sandbox isolates HOME, the root and `claude`, and not one signal. This suite
# once ran the script's real `pkill -f` on every run and killed the live lane's
# listener each time. Those three are stubbed in the sandbox bin beside
# `claude`: a call is recorded in `signals.calls` and nothing is sent. The only
# real signals left are by PID, at processes a case started itself — `kill` is
# a shell builtin, and the script's lock needs `kill -0` to be the real one.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENSURE="$REPO_ROOT/scripts/ensure-manager.sh"
WATCH="$REPO_ROOT/scripts/watch-finish.sh"

BASE_PATH='/usr/bin:/bin'

SETUP_LINE='setup has not run; no manager'

# The launch line and the resume line, spelled out here so a change to either
# has to be made twice, on purpose, in two files.
LAUNCH_ARGV='--bg|--name|retroloop-manager|--agent|retroloop:manager|--permission-mode|auto|--model|opus|--settings|{"crossSessionInbound":"accept"}|start the resolve lane'
LAUNCH_ARGV_FABLE='--bg|--name|retroloop-manager|--agent|retroloop:manager|--permission-mode|auto|--model|fable|--settings|{"crossSessionInbound":"accept"}|start the resolve lane'
# A resume carries NO options besides the id and --bg: a background session
# restores its own saved options on an in-place resume, and any option passed
# starts a copy under a new id instead.
RESUME_ARGV='--resume|old-1111-2222-3333|--bg|resume the resolve lane'

# The same two lines when the caller names the retrospective it just finished:
# the prompt grows one clause and nothing else moves.
LAUNCH_ARGV_FINISHED='--bg|--name|retroloop-manager|--agent|retroloop:manager|--permission-mode|auto|--model|opus|--settings|{"crossSessionInbound":"accept"}|start the resolve lane; retrospective 18 just finished and is yours'
RESUME_ARGV_FINISHED='--resume|old-1111-2222-3333|--bg|resume the resolve lane; retrospective 18 just finished and is yours'

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
  : >"$SB/signals.calls"
  printf '%s\n' "$MINTED" >"$SB/mint"
  SB_PATH="$SB/bin:$BASE_PATH"
  write_claude_stub
  write_signal_stubs
}

# The commands that signal, or pick, a process by what its command line looks
# like. Each stub records its argv and sends nothing; exit 1 is what the real
# ones answer when nothing matched.
SIGNAL_BY_NAME='pkill pgrep killall'

write_signal_stubs() {
  local name
  for name in $SIGNAL_BY_NAME; do
    {
      printf '#!/bin/sh\n'
      printf "SB='%s'\n" "$SB"
      printf "line='%s'\n" "$name"
      cat <<'STUB'
for a in "$@"; do line="$line|$a"; done
printf '%s\n' "$line" >>"$SB/signals.calls"
exit 1
STUB
    } >"$SB/bin/$name"
    chmod +x "$SB/bin/$name"
  done
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

# Processes a case started itself, by pid — the only things this suite ever
# signals. Whatever a failing case left running is put down here.
SPAWNED=''

cleanup() {
  local d p
  for p in $SPAWNED; do kill "$p" 2>/dev/null; done
  for d in $SANDBOXES; do
    for p in $(cat "$d"/*/sleep.pids 2>/dev/null); do kill "$p" 2>/dev/null; done
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
  # Whatever the case was about: the script never picks a process by name.
  if [ -n "$SB" ] && [ -s "$SB/signals.calls" ]; then
    miss "signalled by name: [$(tr '\n' ' ' <"$SB/signals.calls")]"
  fi
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

run_ensure_args() { # <script args...> — same sandbox, arguments to the script
  local errf="$SB/stderr.txt"
  OUT="$(env -i HOME="$SB/home" PATH="$SB_PATH" RETROLOOP_HOME="$SB/root" bash "$ENSURE" "$@" 2>"$errf" </dev/null)"
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

alive() { # <pid>
  case "${1:-}" in '' | *[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null
}

gone_soon() { # <pid> — true once it is dead; a signalled process is given two seconds
  local tries=0
  while [ "$tries" -lt 20 ] && alive "$1"; do
    /bin/sleep 0.1
    tries=$((tries + 1))
  done
  ! alive "$1"
}

# ── the watch, and its PID file ──────────────────────────────────────────────
watch_pid_file() {
  printf '%s' "$SB/root/agents/manager/watch-finish.pid"
}

watch_field() { # <watch|owners|wait>
  sed -n "s/^$1=//p" "$(watch_pid_file)" 2>/dev/null | head -n1
}

wait_for_watch() { # until the PID file names a wait, or five seconds
  local tries=0
  while [ "$tries" -lt 50 ] && ! grep -q '^wait=[0-9]' "$(watch_pid_file)" 2>/dev/null; do
    /bin/sleep 0.1
    tries=$((tries + 1))
  done
}

# A `retroloop` whose wait never returns. It stays a shell, so the words
# `review wait --any` stay on its command line the way they do on the real
# CLI's; the sleep it waits on is recorded so the suite can clear it up.
write_hanging_cli() {
  mkdir -p "$SB/cli"
  cat >"$SB/cli/retroloop" <<'CLI'
#!/bin/sh
/bin/sleep 30 &
printf '%s\n' "$!" >>"$(dirname "$0")/sleep.pids"
wait $!
CLI
  chmod +x "$SB/cli/retroloop"
}

# The REAL watch-finish.sh, armed under this sandbox's root — so the file the
# reap reads is the one the watch really writes, and the two cannot drift.
#   attached  armed by this suite's own shell, which is still here at the reap
#   orphaned  armed by a shell that then goes away, which is what a stopped
#             manager is to the watch it left behind. That shell holds on until
#             the watch has written down who armed it.
WATCH_PID=''
WAIT_PID=''

start_watch() { # <attached|orphaned>
  write_hanging_cli
  if [ "$1" = 'orphaned' ]; then
    (
      env -i HOME="$SB/home" PATH="$SB/cli:$SB/bin:$BASE_PATH" RETROLOOP_HOME="$SB/root" \
        bash "$WATCH" >/dev/null 2>&1 </dev/null &
      wait_for_watch
    )
  else
    env -i HOME="$SB/home" PATH="$SB/cli:$SB/bin:$BASE_PATH" RETROLOOP_HOME="$SB/root" \
      bash "$WATCH" >/dev/null 2>&1 </dev/null &
    wait_for_watch
  fi
  WATCH_PID="$(watch_field watch)"
  WAIT_PID="$(watch_field wait)"
  SPAWNED="$SPAWNED $WATCH_PID $WAIT_PID"
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
begin C5 'model: fable in retroloop.md — the launch runs --model fable'
new_sandbox
make_plugin
cat >"$SB/root/plugins/my/retroloop.md" <<'NOTE'
model: fable
subagent model: opus
tracking: this tool only
NOTE
run_ensure
expect_eq 'launch argv' "$(launch_line)" "$LAUNCH_ARGV_FABLE"
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
# The stub goes, and the sandbox bin stays on PATH: it is also where the
# signal stubs are, and no case runs with the real ones in reach.
rm -f "$SB/bin/claude"
run_ensure
[ "$RC" -ne 0 ] || miss "exit: got 0, want non-zero"
expect_contains 'stderr' "$ERR" 'ensure-manager:'
expect_contains 'stderr names the missing command' "$ERR" 'claude'
expect_eq 'stdout' "$OUT" ''
expect_no_lock
end

# ── C11 · --finished on a launch ─────────────────────────────────────────────
begin C11 '--finished 18 on a fresh launch — the prompt names the retrospective'
new_sandbox
make_plugin
run_ensure_args --finished 18
expect_eq 'stdout' "$OUT" "running $MINTED"
expect_eq 'exit' "$RC" '0'
expect_eq 'launch argv' "$(launch_line)" "$LAUNCH_ARGV_FINISHED"
end

# ── C12 · --finished on a resume ─────────────────────────────────────────────
begin C12 '--finished 18 on a resume — the prompt names it, the options stay off'
new_sandbox
make_plugin
seed_row stopped retroloop-manager "$SB/root/plugins/my" 'old-1111-2222-3333' 1789295248826
run_ensure_args --finished 18
expect_eq 'resume argv' "$(launch_line)" "$RESUME_ARGV_FINISHED"
expect_not_contains 'the resume' "$(launch_line)" '--name'
expect_eq 'exit' "$RC" '0'
end

# ── C13 · --finished wants a number ──────────────────────────────────────────
begin C13 '--finished with no number, or a word — usage, exit 2, nothing launched'
new_sandbox
make_plugin
run_ensure_args --finished
expect_eq 'exit (missing)' "$RC" '2'
run_ensure_args --finished eighteen
expect_eq 'exit (word)' "$RC" '2'
expect_eq 'launches' "$(launch_count)" '0'
end

# ── C14 · --finished when a manager is already up ────────────────────────────
begin C14 '--finished 18 with a live manager — reported, nothing launched'
new_sandbox
make_plugin
seed_row live retroloop-manager "$SB/root/plugins/my" 'live-0000-0000-0000' 1789295248826
run_ensure_args --finished 18
expect_eq 'stdout' "$OUT" 'running live-0000-0000-0000'
expect_eq 'launches' "$(launch_count)" '0'
end

# ── C15 · somebody else's wait ───────────────────────────────────────────────
# The live lane's listener, as this sandbox sees it: a process under no root
# the sandbox knows, with the words `review wait --any` on its command line.
# A full launch must leave it running. (If it is dead and `signals.calls` is
# empty, this script did not do it — an older checkout's suite, running on the
# same machine, still sends the real thing.)
begin C15 'a foreign `review wait --any` on this machine — survives a full launch, and nothing is signalled by name'
new_sandbox
make_plugin
mkdir -p "$SB/decoy"
cat >"$SB/decoy/retroloop" <<'DECOY'
#!/bin/sh
/bin/sleep 30 &
printf '%s\n' "$!" >>"$(dirname "$0")/sleep.pids"
wait $!
DECOY
chmod +x "$SB/decoy/retroloop"
"$SB/decoy/retroloop" review wait --any --follow --timeout 600 --json &
DECOY_PID=$!
SPAWNED="$SPAWNED $DECOY_PID"
/bin/sleep 0.3
expect_contains 'the decoy carries the words' "$(ps -o command= -p "$DECOY_PID" 2>/dev/null)" 'review wait --any'
run_ensure
expect_eq 'stdout' "$OUT" "running $MINTED"
expect_eq 'launches' "$(launch_count)" '1'
alive "$DECOY_PID" || miss "the foreign wait [$DECOY_PID] did not survive the run"
expect_eq 'signalled by name' "$(cat "$SB/signals.calls")" ''
expect_eq 'pkill, as the script would find it' "$(PATH="$SB_PATH" command -v pkill)" "$SB/bin/pkill"
expect_eq 'pgrep, as the script would find it' "$(PATH="$SB_PATH" command -v pgrep)" "$SB/bin/pgrep"
kill "$DECOY_PID" 2>/dev/null
end

# ── C16 · this root's own orphan ─────────────────────────────────────────────
begin C16 "this root's orphaned watch — reaped by pid, with the wait it held, and the PID file cleared"
new_sandbox
make_plugin
start_watch orphaned
alive "$WATCH_PID" || miss "the watch [$WATCH_PID] was not running before the launch"
alive "$WAIT_PID" || miss "the wait [$WAIT_PID] was not running before the launch"
run_ensure
expect_eq 'stdout' "$OUT" "running $MINTED"
expect_eq 'launches' "$(launch_count)" '1'
gone_soon "$WATCH_PID" || miss "the orphaned watch [$WATCH_PID] outlived the launch"
gone_soon "$WAIT_PID" || miss "the orphaned wait [$WAIT_PID] outlived the launch"
[ ! -e "$(watch_pid_file)" ] || miss "the PID file outlived the reap"
end

# ── C17 · a watch that still answers to somebody ─────────────────────────────
# The session list said no manager was live, and the watch's own parents say
# otherwise. The parents win: a leaked process is a leak, a killed listener is
# a deaf lane.
begin C17 'a watch still held by the shell that armed it — left alone, PID file and all'
new_sandbox
make_plugin
start_watch attached
run_ensure
expect_eq 'stdout' "$OUT" "running $MINTED"
alive "$WATCH_PID" || miss "the attached watch [$WATCH_PID] was killed"
alive "$WAIT_PID" || miss "the attached wait [$WAIT_PID] was killed"
expect_eq 'the PID file still names it' "$(watch_field watch)" "$WATCH_PID"
kill "$WATCH_PID" 2>/dev/null
end

# ── C18 · a stale PID file ───────────────────────────────────────────────────
# A watch that died hard leaves its file behind, and pids are reused. The
# process that holds those numbers now is a stranger.
begin C18 'a stale PID file whose pids belong to something else now — the stranger lives, the file goes'
new_sandbox
make_plugin
(
  /bin/sleep 30 &
  printf '%s\n' "$!" >"$SB/stranger.pid"
)
STRANGER="$(cat "$SB/stranger.pid")"
SPAWNED="$SPAWNED $STRANGER"
mkdir -p "$SB/root/agents/manager"
printf 'watch=%s\nowners=9 9\nwait=%s\n' "$STRANGER" "$STRANGER" >"$(watch_pid_file)"
run_ensure
expect_eq 'stdout' "$OUT" "running $MINTED"
alive "$STRANGER" || miss "the stranger [$STRANGER] was killed on the word of a stale PID file"
[ ! -e "$(watch_pid_file)" ] || miss "the stale PID file outlived the reap"
kill "$STRANGER" 2>/dev/null
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=18
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
