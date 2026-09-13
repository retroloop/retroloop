#!/usr/bin/env bash
#
# Acceptance suite — the version monitor (`scripts/version-drift.sh` and
# `monitors/monitors.json`).
#
#   bash tests/version-drift.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# THE SESSION THAT DOES NOT KNOW IT IS BEHIND. A Claude Code session loads a
# plugin once, at its start. When the loop releases a new version into the
# local marketplace, every session already open keeps running the old one —
# happily, invisibly, until someone types /reload-plugins. This monitor is the
# one thing that tells them. So the two failures worth testing are the two that
# make it useless: saying nothing when a session IS behind, and nagging a
# session that is not.
#
# It also pins the shape the monitor loader needs. A plugin monitor's command
# is expanded before it runs, and a brace-wrapped variable is consumed at that
# point — so the script and the command line that starts it must not contain
# one anywhere (F6, F7). That is a rule a reader cannot guess from the code, so
# it is a test.
#
# Every case runs under `env -i` in its own sandbox: a temp HOME, a temp
# RETROLOOP_HOME holding a marketplace and its plugins, and a temp
# CLAUDE_CONFIG_DIR holding the installed-plugins pin file.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIFT="$REPO_ROOT/scripts/version-drift.sh"
MONITORS="$REPO_ROOT/monitors/monitors.json"

BASE_PATH='/usr/bin:/bin'

drifted_line() { # <key> <pin> <source>
  printf '%s: installed %s, source %s. Plugin released as %s. In any Claude Code session that is already open, type /reload-plugins once. New sessions need nothing.' "$1" "$2" "$3" "$3"
}

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SANDBOXES=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl50v-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/root/plugins/.claude-plugin" "$SB/claude/plugins"
}

# The local marketplace: the plugins folder is the marketplace, one entry per
# plugin the loop has built.
write_marketplace() { # <plugin name> <source>...
  local entries='' name src
  while [ "$#" -ge 2 ]; do
    name="$1"
    src="$2"
    shift 2
    [ -z "$entries" ] || entries="$entries,"
    entries="$entries
    {
      \"name\": \"$name\",
      \"source\": \"$src\",
      \"description\": \"A personalization plugin.\"
    }"
  done
  cat >"$SB/root/plugins/.claude-plugin/marketplace.json" <<JSON
{
  "name": "my-marketplace",
  "owner": { "name": "me" },
  "plugins": [$entries
  ]
}
JSON
}

# A plugin in the marketplace folder, at the version its source is on now.
write_plugin() { # <folder> <name> <version>
  mkdir -p "$SB/root/plugins/$1/.claude-plugin"
  cat >"$SB/root/plugins/$1/.claude-plugin/plugin.json" <<JSON
{
  "name": "$2",
  "version": "$3"
}
JSON
}

# What Claude Code pinned when it loaded the plugin: the file is real JSON over
# many lines, with the version buried in an array.
write_pins() { # [<dir>] <key> <version>... — dir defaults to the sandbox config
  local dir="$SB/claude" body='' key ver
  case "$1" in
    /*)
      dir="$1"
      shift
      ;;
  esac
  while [ "$#" -ge 2 ]; do
    key="$1"
    ver="$2"
    shift 2
    [ -z "$body" ] || body="$body,"
    body="$body
    \"$key\": [
      {
        \"version\": \"$ver\",
        \"scope\": \"user\"
      }
    ]"
  done
  mkdir -p "$dir/plugins"
  cat >"$dir/plugins/installed_plugins.json" <<JSON
{
  "version": 1,
  "plugins": {$body
  }
}
JSON
}

move_pin() { # <key> <version> — rewrite the pin file with one new version
  write_pins "$1" "$2"
}

cleanup() {
  local d
  for d in $SANDBOXES; do
    case "$d" in
      */rl50v-*) rm -rf "$d" ;;
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

skip() { # <why> — the case could not run here; it is neither a pass nor a fail
  printf 'SKIP %s — %s (%s)\n' "$CASE" "$CASE_DESC" "$1"
  SKIPPED="$SKIPPED $CASE"
}
SKIPPED=''

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
RC=0
LINES=0

run_drift() { # <arg>...
  OUT="$(env -i HOME="$SB/home" PATH="$BASE_PATH" RETROLOOP_HOME="$SB/root" \
    CLAUDE_CONFIG_DIR="$SB/claude" bash "$DRIFT" "$@" 2>&1 </dev/null)"
  RC=$?
  if [ -z "$OUT" ]; then
    LINES=0
  else
    LINES="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  fi
}

# Same, without CLAUDE_CONFIG_DIR: the pin file is found under HOME instead.
run_drift_default_config() {
  OUT="$(env -i HOME="$SB/home" PATH="$BASE_PATH" RETROLOOP_HOME="$SB/root" \
    bash "$DRIFT" 2>&1 </dev/null)"
  RC=$?
  if [ -z "$OUT" ]; then
    LINES=0
  else
    LINES="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  fi
}

# ── preflight ────────────────────────────────────────────────────────────────
[ -f "$DRIFT" ] || {
  printf 'ABORT: no script at %s\n' "$DRIFT" >&2
  exit 2
}
[ -f "$MONITORS" ] || {
  printf 'ABORT: no monitor file at %s\n' "$MONITORS" >&2
  exit 2
}

# ── F1 · nothing to say ──────────────────────────────────────────────────────
begin F1 'the pin matches the source — silence'
new_sandbox
write_marketplace my ./my
write_plugin my my 0.1.0
write_pins my@my-marketplace 0.1.0
run_drift
expect_eq 'stdout' "$OUT" ''
expect_eq 'exit' "$RC" '0'
end

# ── F2 · behind ──────────────────────────────────────────────────────────────
begin F2 'the session loaded 0.1.0 and the source is 0.1.1 — one line, once'
new_sandbox
write_marketplace my ./my
write_plugin my my 0.1.1
write_pins my@my-marketplace 0.1.0
run_drift
expect_eq 'lines' "$LINES" '1'
expect_eq 'stdout' "$OUT" "$(drifted_line my@my-marketplace 0.1.0 0.1.1)"
expect_eq 'exit' "$RC" '0'
# The pin file is found under HOME when nothing names a config directory.
write_pins "$SB/home/.claude" my@my-marketplace 0.1.0
run_drift_default_config
expect_eq 'stdout with the default config dir' "$OUT" "$(drifted_line my@my-marketplace 0.1.0 0.1.1)"
end

# ── F3 · nothing to read ─────────────────────────────────────────────────────
begin F3 'no pin file, and no marketplace — silence, and never a failure'
new_sandbox
write_marketplace my ./my
write_plugin my my 0.1.1
run_drift
expect_eq 'stdout with no pin file' "$OUT" ''
expect_eq 'exit with no pin file' "$RC" '0'

new_sandbox
write_pins my@my-marketplace 0.1.0
run_drift
expect_eq 'stdout with no marketplace' "$OUT" ''
expect_eq 'exit with no marketplace' "$RC" '0'

# A plugin in the marketplace that this machine never installed is not drift.
new_sandbox
write_marketplace my ./my
write_plugin my my 0.1.1
write_pins other@my-marketplace 9.9.9
run_drift
expect_eq 'stdout for an uninstalled plugin' "$OUT" ''
end

# ── F4 · one of several ──────────────────────────────────────────────────────
begin F4 'two plugins, one behind — only the one behind is named'
new_sandbox
write_marketplace my ./my work ./work
write_plugin my my 0.1.0
write_plugin work work 2.1.0
write_pins my@my-marketplace 0.1.0 work@my-marketplace 2.0.0
run_drift
expect_eq 'lines' "$LINES" '1'
expect_eq 'stdout' "$OUT" "$(drifted_line work@my-marketplace 2.0.0 2.1.0)"
end

# ── F5 · the watch ───────────────────────────────────────────────────────────
begin F5 'the pin moves under a running watch — said once, not once per round'
new_sandbox
write_marketplace my ./my
write_plugin my my 0.1.1
write_pins my@my-marketplace 0.1.1
env -i HOME="$SB/home" PATH="$BASE_PATH" RETROLOOP_HOME="$SB/root" \
  CLAUDE_CONFIG_DIR="$SB/claude" bash "$DRIFT" --watch 1 --rounds 3 \
  >"$SB/watch.out" 2>"$SB/watch.err" </dev/null &
watch_pid=$!
sleep 1.5
move_pin my@my-marketplace 0.0.9
wait "$watch_pid"
watch_rc=$?
expect_eq 'exit' "$watch_rc" '0'
expect_eq 'lines' "$(wc -l <"$SB/watch.out" | tr -d ' ')" '1'
expect_contains 'the line' "$(cat "$SB/watch.out")" 'my@my-marketplace: installed 0.0.9, source 0.1.1.'
expect_eq 'stderr' "$(cat "$SB/watch.err")" ''

# And the case the pin alone can tell: a release lands while the watch is up,
# so the pin and the source agree again — on a version this session did not
# load. One round, timed to fall well after both files have settled.
new_sandbox
write_marketplace my ./my
write_plugin my my 0.1.1
write_pins my@my-marketplace 0.1.1
env -i HOME="$SB/home" PATH="$BASE_PATH" RETROLOOP_HOME="$SB/root" \
  CLAUDE_CONFIG_DIR="$SB/claude" bash "$DRIFT" --watch 2 --rounds 1 \
  >"$SB/watch.out" 2>"$SB/watch.err" </dev/null &
watch_pid=$!
sleep 0.2
write_plugin my my 0.1.2
move_pin my@my-marketplace 0.1.2
wait "$watch_pid"
expect_eq 'a moved pin is drift even when it matches the source' \
  "$(cat "$SB/watch.out")" "$(drifted_line my@my-marketplace 0.1.2 0.1.2)"
end

# ── F6 · no brace forms in the script ────────────────────────────────────────
begin F6 'the script contains no brace-wrapped variable anywhere'
if grep -n -F '${' "$DRIFT" >/dev/null 2>&1; then
  miss "$(printf '%s uses a brace form:\n' "$DRIFT")$(grep -n -F '${' "$DRIFT" | head -n5)"
fi
end

# ── F7 · the monitor entry ───────────────────────────────────────────────────
begin F7 'monitors.json is one monitor that runs the script, brace-free'
if ! PATH="$BASE_PATH" command -v python3 >/dev/null 2>&1; then
  skip 'no python3 to parse JSON with'
else
  report="$(PATH="$BASE_PATH" python3 - "$MONITORS" <<'PY'
import json, sys
problems = []
with open(sys.argv[1]) as f:
    data = json.load(f)
if not isinstance(data, list):
    problems.append("the file is %s, not an array" % type(data).__name__)
elif len(data) != 1:
    problems.append("%d entries, want exactly 1" % len(data))
else:
    entry = data[0]
    name = entry.get("name", "")
    if name != "retroloop-version":
        problems.append("name is [%s], want [retroloop-version]" % name)
    if not entry.get("description", "").strip():
        problems.append("no description")
    command = entry.get("command", "")
    if "scripts/version-drift.sh" not in command:
        problems.append("the command does not run scripts/version-drift.sh")
    if "${" in command:
        problems.append("the command uses a brace form")
for p in problems:
    print(p)
PY
  )" || miss "monitors.json did not parse as JSON"
  [ -z "$report" ] || miss "$report"
  end
fi

# ── verdict ──────────────────────────────────────────────────────────────────
total=7
n_failed=0
n_skipped=0
for _ in $FAILED_IDS; do n_failed=$((n_failed + 1)); done
for _ in $SKIPPED; do n_skipped=$((n_skipped + 1)); done
n_passed=$((total - n_failed - n_skipped))

printf '\n%d cases: %d passed, %d failed' "$total" "$n_passed" "$n_failed"
[ "$n_skipped" -eq 0 ] || printf ', %d skipped' "$n_skipped"
if [ -n "$FAILED_IDS" ]; then
  printf ' —%s\n' "$FAILED_IDS"
  exit 1
fi
printf '\n'
exit 0
