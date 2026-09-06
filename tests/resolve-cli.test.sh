#!/usr/bin/env bash
#
# RL-02 acceptance suite — the shared CLI resolver (`scripts/resolve-cli.sh`),
# the SessionStart hook, and `watch-review.sh where`.
#
#   bash tests/resolve-cli.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# Every case runs in its own sandbox: a temp HOME, a temp PATH holding only a
# directory the case controls plus /usr/bin:/bin, and RETROLOOP_HOME,
# RETRO_HOME, RETROLOOP_APP and WATCH_REVIEW_CLI unset unless the case sets
# them (the child is started under `env -i`, so nothing leaks in from here).
# `bun` is never needed: the resolver decides a command, it never runs one.
#
# Three probes, one per surface:
#   run_hook       runs hooks/session-start.sh and captures its one line
#   run_resolver   sources scripts/resolve-cli.sh in a subshell and reports
#                  RETROLOOP_CLI_SOURCE + RETROLOOP_CLI
#   run_where      runs scripts/watch-review.sh where

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/session-start.sh"
WATCH="$REPO_ROOT/scripts/watch-review.sh"
RESOLVER="$REPO_ROOT/scripts/resolve-cli.sh"

TRACKED='This session is tracked by Retroloop: keep friction notes (skill: notes); /retroloop:review when the session winds down.'
NOT_SET_UP='Retroloop is installed but not set up — run /retroloop:setup'

BASE_PATH='/usr/bin:/bin'

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SANDBOXES=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl02-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin"
  fake_checkout "$SB/checkout"
}

# A fake app checkout is a directory with an empty apps/cli/src/bin.ts in it.
fake_checkout() {
  mkdir -p "$1/apps/cli/src"
  : >"$1/apps/cli/src/bin.ts"
}

fake_retroloop_on_path() {
  printf '#!/bin/sh\nprintf "0.0.0-fake\\n"\n' >"$SB/bin/retroloop"
  chmod +x "$SB/bin/retroloop"
}

write_pointer() { # <home dir> <content>
  mkdir -p "$1"
  printf '%s\n' "$2" >"$1/app-path"
}

cleanup() {
  local d
  for d in $SANDBOXES; do
    case "$d" in
      */rl02-*) rm -rf "$d" ;;
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
SHAPE_VIOLATIONS=''

begin() {
  CASE="$1"
  CASE_DESC="$2"
  CASE_FAILED=0
  DETAIL=''
}

miss() { # record one failed expectation
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
HOOK_OUT=''
HOOK_RC=0
HOOK_LINES=0

run_hook() { # [VAR=VALUE ...]
  HOOK_OUT="$(env -i HOME="$SB/home" PATH="$SB/bin:$BASE_PATH" "$@" bash "$HOOK" 2>/dev/null </dev/null)"
  HOOK_RC=$?
  if [ -z "$HOOK_OUT" ]; then
    HOOK_LINES=0
  else
    HOOK_LINES="$(printf '%s\n' "$HOOK_OUT" | wc -l | tr -d ' ')"
  fi
  # A13 is asserted on every hook invocation in the suite, not in a case of
  # its own: exactly one line on stdout, exit 0, always.
  if [ "$HOOK_RC" -ne 0 ] || [ "$HOOK_LINES" -ne 1 ]; then
    SHAPE_VIOLATIONS="$SHAPE_VIOLATIONS     $CASE: exit=$HOOK_RC lines=$HOOK_LINES"$'\n'
  fi
}

expect_hook() { # <expected line>
  expect_eq 'hook line' "$HOOK_OUT" "$1"
  expect_eq 'hook exit' "$HOOK_RC" '0'
}

RES_RC=0
RES_SOURCE=''
RES_CLI=''

run_resolver() { # [VAR=VALUE ...]
  local out
  out="$(env -i HOME="$SB/home" PATH="$SB/bin:$BASE_PATH" "$@" bash -c '
    set -uo pipefail
    [ -f "$1" ] || exit 3
    . "$1"
    retroloop_resolve_cli || exit 1
    printf "%s\n" "$RETROLOOP_CLI_SOURCE"
    printf "%s\n" ${RETROLOOP_CLI[@]+"${RETROLOOP_CLI[@]}"}
  ' rl02-probe "$RESOLVER" 2>/dev/null)"
  RES_RC=$?
  if [ "$RES_RC" -eq 0 ]; then
    RES_SOURCE="$(printf '%s\n' "$out" | sed -n '1p')"
    RES_CLI="$(printf '%s\n' "$out" | sed -n '2,$p' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  else
    RES_SOURCE=''
    RES_CLI=''
  fi
}

expect_resolution() { # <source> <cli>
  if [ "$RES_RC" -eq 3 ]; then
    miss "resolver: $RESOLVER does not exist"
    return
  fi
  if [ "$RES_RC" -ne 0 ]; then
    miss "resolver: returned $RES_RC (a miss) — expected source [$1]"
    return
  fi
  expect_eq 'resolver source' "$RES_SOURCE" "$1"
  expect_eq 'resolver cli' "$RES_CLI" "$2"
}

expect_resolver_miss() {
  [ "$RES_RC" -ne 0 ] || miss "resolver: resolved to [$RES_CLI] ($RES_SOURCE) — expected a miss"
}

WHERE_OUT=''

run_where() { # [VAR=VALUE ...]
  # cwd is the sandbox, so the resolver's repo step (git rev-parse) finds
  # nothing and cannot mask the step under test.
  WHERE_OUT="$(cd "$SB" && env -i HOME="$SB/home" PATH="$SB/bin:$BASE_PATH" "$@" bash "$WATCH" where 2>&1 </dev/null)"
}

# ── preflight ────────────────────────────────────────────────────────────────
preflight() {
  local stray
  if stray="$(PATH="$BASE_PATH" command -v retroloop 2>/dev/null)" && [ -n "$stray" ]; then
    printf 'ABORT: a real retroloop is on the base PATH (%s); the sandbox cannot isolate PATH.\n' "$stray" >&2
    exit 2
  fi
  [ -f "$HOOK" ] || { printf 'ABORT: no hook at %s\n' "$HOOK" >&2; exit 2; }
  [ -f "$WATCH" ] || { printf 'ABORT: no watch script at %s\n' "$WATCH" >&2; exit 2; }
}
preflight

# ── A1 · nothing resolves ────────────────────────────────────────────────────
begin A1 'nothing resolves — not-set-up line, and `where` says <none>'
new_sandbox
run_hook
expect_hook "$NOT_SET_UP"
run_where
expect_contains 'where' "$WHERE_OUT" '<none'
end

# ── A2 · PATH ────────────────────────────────────────────────────────────────
begin A2 'retroloop on PATH'
new_sandbox
fake_retroloop_on_path
run_hook
expect_hook "$TRACKED"
run_resolver
expect_resolution 'path' "$SB/bin/retroloop"
end

# ── A3 · env, directory form ─────────────────────────────────────────────────
begin A3 'RETROLOOP_APP is an app checkout directory'
new_sandbox
run_hook RETROLOOP_APP="$SB/checkout"
expect_hook "$TRACKED"
run_resolver RETROLOOP_APP="$SB/checkout"
expect_resolution 'env' "bun $SB/checkout/apps/cli/src/bin.ts"
end

# ── A4 · env, file form ──────────────────────────────────────────────────────
begin A4 'RETROLOOP_APP is a .ts CLI entry'
new_sandbox
run_hook RETROLOOP_APP="$SB/checkout/apps/cli/src/bin.ts"
expect_hook "$TRACKED"
run_resolver RETROLOOP_APP="$SB/checkout/apps/cli/src/bin.ts"
expect_resolution 'env' "bun $SB/checkout/apps/cli/src/bin.ts"
end

# ── A5 · env unusable falls through ──────────────────────────────────────────
begin A5 'RETROLOOP_APP set but unusable — falls through, no crash'
new_sandbox
run_hook RETROLOOP_APP=/nonexistent
expect_hook "$NOT_SET_UP"
run_where RETROLOOP_APP=/nonexistent
expect_contains 'where names the variable' "$WHERE_OUT" 'RETROLOOP_APP'
expect_contains 'where calls it unusable' "$WHERE_OUT" 'set but unusable'
end

# ── A6 · WATCH_REVIEW_CLI alias ──────────────────────────────────────────────
begin A6 'WATCH_REVIEW_CLI kept as a compatibility alias'
new_sandbox
run_hook WATCH_REVIEW_CLI='bun /tmp/x/bin.ts'
expect_hook "$TRACKED"
run_resolver WATCH_REVIEW_CLI='bun /tmp/x/bin.ts'
expect_resolution 'env' 'bun /tmp/x/bin.ts'
run_where WATCH_REVIEW_CLI='bun /tmp/x/bin.ts'
expect_contains 'where' "$WHERE_OUT" 'bun /tmp/x/bin.ts'
# All whitespace is no command at all, and no command is a miss.
run_hook WATCH_REVIEW_CLI='   '
expect_hook "$NOT_SET_UP"
run_resolver WATCH_REVIEW_CLI='   '
expect_resolver_miss
end

# ── A7 · pointer file under RETROLOOP_HOME ───────────────────────────────────
begin A7 'pointer file under RETROLOOP_HOME'
new_sandbox
write_pointer "$SB/rlhome" "$SB/checkout"
run_hook RETROLOOP_HOME="$SB/rlhome"
expect_hook "$TRACKED"
run_resolver RETROLOOP_HOME="$SB/rlhome"
expect_resolution 'pointer' "bun $SB/checkout/apps/cli/src/bin.ts"
end

# ── A8 · pointer file under RETRO_HOME ───────────────────────────────────────
begin A8 'pointer file under RETRO_HOME (RETROLOOP_HOME unset)'
new_sandbox
write_pointer "$SB/rthome" "$SB/checkout"
run_hook RETRO_HOME="$SB/rthome"
expect_hook "$TRACKED"
run_resolver RETRO_HOME="$SB/rthome"
expect_resolution 'pointer' "bun $SB/checkout/apps/cli/src/bin.ts"
end

# ── A9 · pointer file under the default home ─────────────────────────────────
begin A9 'pointer file under $HOME/.ai-team/retro'
new_sandbox
write_pointer "$SB/home/.ai-team/retro" "$SB/checkout"
run_hook
expect_hook "$TRACKED"
run_resolver
expect_resolution 'pointer' "bun $SB/checkout/apps/cli/src/bin.ts"
end

# ── A10 · pointer unusable falls through ─────────────────────────────────────
begin A10 'pointer file names a path that is not there'
new_sandbox
write_pointer "$SB/home/.ai-team/retro" '/nonexistent'
run_hook
expect_hook "$NOT_SET_UP"
run_resolver
expect_resolver_miss
end

# ── A11 · the historical default ─────────────────────────────────────────────
begin A11 'default checkout at $HOME/Developer/retroloop-app'
new_sandbox
fake_checkout "$SB/home/Developer/retroloop-app"
run_hook
expect_hook "$TRACKED"
run_resolver
expect_resolution 'default' "bun $SB/home/Developer/retroloop-app/apps/cli/src/bin.ts"
end

# ── A12 · first hit wins ─────────────────────────────────────────────────────
begin A12 'first hit wins — PATH>env, env>pointer, pointer>default'
new_sandbox
fake_retroloop_on_path
run_resolver RETROLOOP_APP="$SB/checkout"
expect_resolution 'path' "$SB/bin/retroloop"

new_sandbox
fake_checkout "$SB/pointed-at"
write_pointer "$SB/rlhome" "$SB/pointed-at"
run_resolver RETROLOOP_APP="$SB/checkout" RETROLOOP_HOME="$SB/rlhome"
expect_resolution 'env' "bun $SB/checkout/apps/cli/src/bin.ts"

new_sandbox
fake_checkout "$SB/home/Developer/retroloop-app"
write_pointer "$SB/rlhome" "$SB/checkout"
run_resolver RETROLOOP_HOME="$SB/rlhome"
expect_resolution 'pointer' "bun $SB/checkout/apps/cli/src/bin.ts"
end

# ── A13 · the hook's shape, across every case above ──────────────────────────
begin A13 'the hook always prints exactly one line and exits 0'
if [ -n "$SHAPE_VIOLATIONS" ]; then
  CASE_FAILED=1
  DETAIL="$SHAPE_VIOLATIONS"
fi
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=13
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
