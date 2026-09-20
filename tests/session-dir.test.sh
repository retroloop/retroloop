#!/usr/bin/env bash
#
# Acceptance suite — the session folder under one root.
#
#   bash tests/session-dir.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# Two hooks, one contract. The root is `$RETROLOOP_HOME`, else `~/.retroloop`;
# a session's evidence lives at `<root>/sessions/<session_id>/`.
#
#   SessionStart  reads `session_id` off the hook's stdin JSON and prints ONE
#                 line naming `<root>/sessions/<id>/notes.md`. It CREATES
#                 NOTHING: the folder appears on the first write, which is the
#                 notes skill's, never a session start's. No session id → the
#                 old line, without a path.
#   PreCompact    copies `<root>/sessions/<id>/notes.md` into
#                 `<root>/sessions/<id>/snapshots/<YYYYMMDD-HHMMSS>.md` and
#                 says where. No id or no notes file → no write, no output.
#                 Always exit 0: compaction is never blocked.
#
# Every case runs under `env -i` in its own sandbox — a temp HOME, a temp root,
# a temp PATH — so nothing from the developer's machine can answer for the
# code under test. The whole point of several cases is that a directory does
# NOT appear, so the sandbox is inspected with `find`, before and after.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION_START="$REPO_ROOT/hooks/session-start.sh"
PRE_COMPACT="$REPO_ROOT/hooks/pre-compact.sh"

SID='abc-123'
BASE_PATH='/usr/bin:/bin'

TRACKED_NO_ID='This session is tracked by Retroloop: keep friction notes (skill: notes); /retroloop:review when the session winds down.'

tracked_line() { # <root>
  printf 'This session is tracked by Retroloop: keep friction notes (skill: notes) in %s/sessions/%s/notes.md; /retroloop:review when the session winds down.' "$1" "$SID"
}

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SANDBOXES=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl49-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin"
  # The hook only prints the tracked line when a CLI resolves; PATH is the
  # cheapest way to say "set up" without putting anything inside the root.
  printf '#!/bin/sh\nprintf "0.0.0-fake\\n"\n' >"$SB/bin/retroloop"
  chmod +x "$SB/bin/retroloop"
  printf '{"session_id":"%s","cwd":"/tmp"}\n' "$SID" >"$SB/stdin.json"
  : >"$SB/empty.json"
}

cleanup() {
  local d
  for d in $SANDBOXES; do
    case "$d" in
      */rl49-*) rm -rf "$d" ;;
    esac
  done
}
trap cleanup EXIT

# Everything under a directory, one path per line, sorted — the before/after
# picture a "creates nothing" assertion is made of.
tree_of() { # <dir>
  [ -e "$1" ] || return 0
  find "$1" | sort
}

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

expect_no_path() { # <what> <path>
  [ ! -e "$2" ] || miss "$1: $2 exists and must not"
}

expect_same_tree() { # <what> <before> <after>
  [ "$2" = "$3" ] || miss "$1: the sandbox changed —"$'\n'"       before: [$2]"$'\n'"       after:  [$3]"
}

# ── probes ───────────────────────────────────────────────────────────────────
OUT=''
RC=0
LINES=0

run_hook() { # <script> <stdin file> [VAR=VALUE ...]
  local script="$1" stdin="$2"
  shift 2
  OUT="$(env -i HOME="$SB/home" PATH="$SB/bin:$BASE_PATH" "$@" bash "$script" 2>/dev/null <"$stdin")"
  RC=$?
  if [ -z "$OUT" ]; then
    LINES=0
  else
    LINES="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  fi
  [ "$RC" -eq 0 ] || miss "exit: got $RC want 0 (a hook never fails its event)"
}

expect_one_line() { # <expected line>
  expect_eq 'lines' "$LINES" '1'
  expect_eq 'line' "$OUT" "$1"
}

expect_silent() {
  expect_eq 'output' "$OUT" ''
}

# One snapshot file, named <YYYYMMDD-HHMMSS>.md, and nothing else beside it.
expect_one_snapshot() { # <snapshots dir> <expected content>
  local n=0 f='' only=''
  if [ ! -d "$1" ]; then
    miss "snapshots: $1 is not a directory"
    return
  fi
  for f in "$1"/*; do
    [ -e "$f" ] || continue
    n=$((n + 1))
    only="$f"
  done
  [ "$n" -eq 1 ] || { miss "snapshots: $n files in $1, want exactly 1"; return; }
  case "${only##*/}" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].md) ;;
    *) miss "snapshot name: [${only##*/}] is not <YYYYMMDD-HHMMSS>.md" ;;
  esac
  SNAPSHOT="$only"
  expect_eq 'snapshot content' "$(cat "$only")" "$2"
}
SNAPSHOT=''

write_notes() { # <root> <text>
  mkdir -p "$1/sessions/$SID"
  printf '%s\n' "$2" >"$1/sessions/$SID/notes.md"
}

# ── preflight ────────────────────────────────────────────────────────────────
[ -f "$SESSION_START" ] || { printf 'ABORT: no hook at %s\n' "$SESSION_START" >&2; exit 2; }
[ -f "$PRE_COMPACT" ] || { printf 'ABORT: no hook at %s\n' "$PRE_COMPACT" >&2; exit 2; }
if stray="$(PATH="$BASE_PATH" command -v retroloop 2>/dev/null)" && [ -n "$stray" ]; then
  printf 'ABORT: a real retroloop is on the base PATH (%s); the sandbox cannot isolate PATH.\n' "$stray" >&2
  exit 2
fi

# ── B1 · SessionStart names the session folder, and creates none of it ───────
begin B1 'SessionStart prints <root>/sessions/<id>/notes.md and creates nothing'
new_sandbox
before="$(tree_of "$SB/root")"
run_hook "$SESSION_START" "$SB/stdin.json" RETROLOOP_HOME="$SB/root"
expect_one_line "$(tracked_line "$SB/root")"
expect_contains 'the session path' "$OUT" "sessions/$SID/notes.md"
expect_no_path 'the root' "$SB/root"
expect_same_tree 'the root' "$before" "$(tree_of "$SB/root")"
end

# ── B2 · the default root is printed as the literal ~/.retroloop ─────────────
begin B2 'RETROLOOP_HOME unset — the line reads ~/.retroloop, and $HOME is untouched'
new_sandbox
before="$(tree_of "$SB/home")"
run_hook "$SESSION_START" "$SB/stdin.json"
expect_one_line "$(tracked_line '~/.retroloop')"
expect_no_path 'the default root' "$SB/home/.retroloop"
expect_same_tree 'HOME' "$before" "$(tree_of "$SB/home")"
end

# ── B3 · no session id on stdin ──────────────────────────────────────────────
begin B3 'empty stdin — the line without a path, still exactly one line'
new_sandbox
run_hook "$SESSION_START" "$SB/empty.json" RETROLOOP_HOME="$SB/root"
expect_one_line "$TRACKED_NO_ID"
expect_no_path 'the root' "$SB/root"
end

# ── B4 · PreCompact snapshots the notes ──────────────────────────────────────
begin B4 'PreCompact copies notes.md into snapshots/ and says where'
new_sandbox
write_notes "$SB/root" 'friction: the thing that cost an hour'
run_hook "$PRE_COMPACT" "$SB/stdin.json" RETROLOOP_HOME="$SB/root"
expect_eq 'lines' "$LINES" '1'
expect_one_snapshot "$SB/root/sessions/$SID/snapshots" 'friction: the thing that cost an hour'
expect_contains 'the line names the snapshot' "$OUT" "$SNAPSHOT"
# The notes file is copied, never moved, and nothing else is created: the
# session folder holds exactly notes.md and snapshots/<ts>.md.
expect_eq 'the session folder' \
  "$(tree_of "$SB/root/sessions/$SID" | sed "s#^$SB/root/sessions/$SID##" | sed "s#/snapshots/[0-9-]*\.md#/snapshots/<ts>.md#")" \
  "$(printf '\n/notes.md\n/snapshots\n/snapshots/<ts>.md')"
end

# ── B5 · no notes file ───────────────────────────────────────────────────────
begin B5 'PreCompact with no notes file — no write, no output'
new_sandbox
mkdir -p "$SB/root/sessions/$SID"
before="$(tree_of "$SB/root")"
run_hook "$PRE_COMPACT" "$SB/stdin.json" RETROLOOP_HOME="$SB/root"
expect_silent
expect_no_path 'snapshots/' "$SB/root/sessions/$SID/snapshots"
expect_same_tree 'the root' "$before" "$(tree_of "$SB/root")"
end

# ── B6 · no session id ───────────────────────────────────────────────────────
begin B6 'PreCompact with no session id — no write, no output'
new_sandbox
write_notes "$SB/root" 'notes that belong to some other session'
before="$(tree_of "$SB/root")"
run_hook "$PRE_COMPACT" "$SB/empty.json" RETROLOOP_HOME="$SB/root"
expect_silent
expect_same_tree 'the root' "$before" "$(tree_of "$SB/root")"
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=6
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
