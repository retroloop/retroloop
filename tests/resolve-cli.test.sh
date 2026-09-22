#!/usr/bin/env bash
#
# Acceptance suite — the shared CLI resolver (`scripts/resolve-cli.sh`), the
# SessionStart hook, and `watch-review.sh where`.
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
# The app lives in one fixed place under one root: the root is
# `$RETROLOOP_HOME`, else `~/.retroloop`, and the app is `<root>/apps/retroloop`.
# There is no pointer file of any kind, and `RETRO_HOME` is retired — a set
# `RETRO_HOME` must not move the answer by one character (A9).
#
# Four probes, one per surface:
#   run_hook       runs hooks/session-start.sh and captures its one line
#   run_resolver   sources scripts/resolve-cli.sh in a subshell and reports
#                  RETROLOOP_CLI_SOURCE + RETROLOOP_CLI
#   run_where      runs scripts/watch-review.sh where
#   run_shipped    runs the command the plugin ships in bin/, found by name on
#                  a PATH that carries the plugin's own bin directory — which
#                  is what Claude Code does for every installed plugin. Every
#                  such run is watched by a clock, because the failure it guards
#                  against is the command resolving to itself and exec'ing
#                  forever.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/hooks/session-start.sh"
WATCH="$REPO_ROOT/scripts/watch-review.sh"
RESOLVER="$REPO_ROOT/scripts/resolve-cli.sh"
PLUGIN_BIN="$REPO_ROOT/bin"

# This suite never feeds the hook a session id (every probe runs with stdin on
# /dev/null), so the line under test here is the one the hook prints when it
# cannot read one. The session-folder line has its own suite:
# tests/session-dir.test.sh.
TRACKED='This session is tracked by Retroloop: keep friction notes (skill: notes); /retroloop:review when the session winds down.'
NOT_SET_UP='Retroloop is installed but not set up — run /retroloop:setup'

BASE_PATH='/usr/bin:/bin'

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SANDBOXES=''
# Prepended to the sandbox PATH by the cases that need the plugin's own bin
# directory on it; empty everywhere else, so no case sees the shipped command
# unless it asked for it.
PATH_PREFIX=''
# The bin directory `run_shipped` puts first on PATH. Normally the plugin's own;
# a case that needs a damaged plugin tree points it at its own copy.
SHIPPED_BIN=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl02-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin"
  PATH_PREFIX=''
  SHIPPED_BIN="$PLUGIN_BIN"
  fake_checkout "$SB/checkout"
}

# A fake app checkout is a directory with an empty apps/cli/src/bin.ts in it.
fake_checkout() {
  mkdir -p "$1/apps/cli/src"
  : >"$1/apps/cli/src/bin.ts"
}

# The fixed place: the app checkout inside a root, at <root>/apps/retroloop.
fake_root_checkout() { # <root>
  fake_checkout "$1/apps/retroloop"
}

fake_retroloop_on_path() {
  printf '#!/bin/sh\nprintf "0.0.0-fake\\n"\n' >"$SB/bin/retroloop"
  chmod +x "$SB/bin/retroloop"
}

# The plugin's own bin directory on PATH, the way Claude Code puts it there.
shipped_on_path() { PATH_PREFIX="$PLUGIN_BIN:"; }

# A bun that runs nothing: it prints the command line it was handed and records
# one line per call, so a case can count how many times the app was reached.
fake_bun_on_path() {
  {
    printf '#!/bin/sh\n'
    printf 'printf "call\\n" >>"%s"\n' "$SB/calls"
    printf 'printf "bun"\n'
    printf 'for a in "$@"; do printf " [%%s]" "$a"; done\n'
    printf 'printf "\\n"\n'
  } >"$SB/bin/bun"
  chmod +x "$SB/bin/bun"
  : >"$SB/calls"
}

# An app in the executable reading of RETROLOOP_APP: it prints each argument it
# was given, one per line, and exits with the code the case asks for.
fake_app_executable() { # <path>
  {
    printf '#!/bin/sh\n'
    printf 'for a in "$@"; do printf "arg[%%s]\\n" "$a"; done\n'
    printf 'exit "${RL_FAKE_EXIT:-0}"\n'
  } >"$1"
  chmod +x "$1"
}

calls_made() { # how many times the fake bun was reached
  [ -f "$SB/calls" ] || { printf '0'; return; }
  printf '%s' "$(wc -l <"$SB/calls" | tr -d ' ')"
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

expect_not_contains() { # <what> <haystack> <needle>
  case "$2" in
    *"$3"*) miss "$1: [$2] must not contain [$3]" ;;
  esac
}

# ── probes ───────────────────────────────────────────────────────────────────
HOOK_OUT=''
HOOK_RC=0
HOOK_LINES=0

run_hook() { # [VAR=VALUE ...]
  HOOK_OUT="$(env -i HOME="$SB/home" PATH="$PATH_PREFIX$SB/bin:$BASE_PATH" "$@" bash "$HOOK" 2>/dev/null </dev/null)"
  HOOK_RC=$?
  if [ -z "$HOOK_OUT" ]; then
    HOOK_LINES=0
  else
    HOOK_LINES="$(printf '%s\n' "$HOOK_OUT" | wc -l | tr -d ' ')"
  fi
  # A11 is asserted on every hook invocation in the suite, not in a case of
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
  out="$(env -i HOME="$SB/home" PATH="$PATH_PREFIX$SB/bin:$BASE_PATH" "$@" bash -c '
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
  WHERE_OUT="$(cd "$SB" && env -i HOME="$SB/home" PATH="$PATH_PREFIX$SB/bin:$BASE_PATH" "$@" bash "$WATCH" where 2>&1 </dev/null)"
}

SHIPPED_OUT=''
SHIPPED_RC=0

# run_shipped [VAR=VALUE ...] -- [argument ...]
# Runs `retroloop` by name only, so the case proves what a session gets: the
# plugin's bin directory is first on PATH and nothing else on that PATH carries
# the name.
#
# The watchdog is the depth guard. A command that resolves to itself replaces
# itself with itself for ever — one process, no output, no end — so the run is
# backgrounded and killed after ten seconds. A CPU limit does not do it: the
# looping process spends its time in short-lived children, so it was still
# going after a minute and a half of measured CPU when this was tried.
run_shipped() {
  local -a envs=() args=()
  local sawdashdash=0 a
  for a in "$@"; do
    if [ "$sawdashdash" -eq 0 ] && [ "$a" = '--' ]; then sawdashdash=1; continue; fi
    if [ "$sawdashdash" -eq 0 ]; then envs[${#envs[@]}]="$a"; else args[${#args[@]}]="$a"; fi
  done

  : >"$SB/shipped.out"
  env -i HOME="$SB/home" PATH="${SHIPPED_BIN:-$PLUGIN_BIN}:$SB/bin:$BASE_PATH" \
    ${envs[@]+"${envs[@]}"} retroloop ${args[@]+"${args[@]}"} \
    >"$SB/shipped.out" 2>&1 </dev/null &
  local pid=$! waited=0 alive=1
  while [ "$waited" -lt 100 ]; do
    if kill -0 "$pid" 2>/dev/null; then
      sleep 0.1
      waited=$((waited + 1))
    else
      alive=0
      break
    fi
  done

  if [ "$alive" -eq 1 ]; then
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    SHIPPED_RC=137
    SHIPPED_OUT='(killed after ten seconds — the command never returned, which is what running itself looks like)'
    return
  fi
  wait "$pid" 2>/dev/null
  SHIPPED_RC=$?
  SHIPPED_OUT="$(cat "$SB/shipped.out")"
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
  [ -x "$PLUGIN_BIN/retroloop" ] || { printf 'ABORT: no shipped command at %s\n' "$PLUGIN_BIN/retroloop" >&2; exit 2; }
  [ -f "$PLUGIN_BIN/.retroloop-bin" ] || { printf 'ABORT: no marker beside the shipped command\n' >&2; exit 2; }
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

# ── A7 · the fixed place under the default root ──────────────────────────────
begin A7 'the app at ~/.retroloop/apps/retroloop, no variable set'
new_sandbox
fake_root_checkout "$SB/home/.retroloop"
run_hook
expect_hook "$TRACKED"
run_resolver
expect_resolution 'default' "bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
end

# ── A8 · the root moves with RETROLOOP_HOME ──────────────────────────────────
begin A8 'RETROLOOP_HOME names the root; the app is <root>/apps/retroloop'
new_sandbox
fake_root_checkout "$SB/rlhome"
run_hook RETROLOOP_HOME="$SB/rlhome"
expect_hook "$TRACKED"
run_resolver RETROLOOP_HOME="$SB/rlhome"
expect_resolution 'default' "bun $SB/rlhome/apps/retroloop/apps/cli/src/bin.ts"
# The default root is not consulted once RETROLOOP_HOME is set.
new_sandbox
fake_root_checkout "$SB/home/.retroloop"
run_resolver RETROLOOP_HOME="$SB/empty-root"
expect_resolver_miss
end

# ── A9 · RETRO_HOME is retired ───────────────────────────────────────────────
begin A9 'RETRO_HOME alone is ignored — it names no root any more'
new_sandbox
fake_root_checkout "$SB/rthome"
run_hook RETRO_HOME="$SB/rthome"
expect_hook "$NOT_SET_UP"
run_resolver RETRO_HOME="$SB/rthome"
expect_resolver_miss
# And it cannot outvote the default root either.
new_sandbox
fake_root_checkout "$SB/home/.retroloop"
fake_root_checkout "$SB/rthome"
run_resolver RETRO_HOME="$SB/rthome"
expect_resolution 'default' "bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
end

# ── A10 · first hit wins ─────────────────────────────────────────────────────
begin A10 'first hit wins — PATH>env, PATH>default, env>default'
new_sandbox
fake_retroloop_on_path
run_resolver RETROLOOP_APP="$SB/checkout"
expect_resolution 'path' "$SB/bin/retroloop"

new_sandbox
fake_retroloop_on_path
fake_root_checkout "$SB/home/.retroloop"
run_resolver
expect_resolution 'path' "$SB/bin/retroloop"

new_sandbox
fake_root_checkout "$SB/home/.retroloop"
run_resolver RETROLOOP_APP="$SB/checkout"
expect_resolution 'env' "bun $SB/checkout/apps/cli/src/bin.ts"
end

# ── A12 · the shipped command never resolves to itself ───────────────────────
# Without the marker beside it, step 1 of the resolver — "is `retroloop` on
# PATH" — answers with the shipped command itself, which then runs itself for
# ever. The resolver must look past it and land on the installed app.
begin A12 'the shipped command on PATH is skipped; it reaches the app exactly once'
new_sandbox
shipped_on_path
fake_bun_on_path
fake_root_checkout "$SB/home/.retroloop"
run_resolver
expect_resolution 'default' "bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
run_hook
expect_hook "$TRACKED"
run_shipped -- --version
expect_eq 'shipped exit' "$SHIPPED_RC" '0'
expect_contains 'the shipped command ran the installed app' "$SHIPPED_OUT" \
  "bun [$SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts] [--version]"
expect_eq 'the app was reached exactly once' "$(calls_made)" '1'
end

# ── A13 · shipped, but the app was never installed ───────────────────────────
begin A13 'shipped command present, no app — miss, not-set-up line, and setup is named'
new_sandbox
shipped_on_path
run_resolver
expect_resolver_miss
run_hook
expect_hook "$NOT_SET_UP"
run_shipped -- --version
if [ "$SHIPPED_RC" -eq 0 ]; then
  miss "shipped command: exited 0 with no app installed"
fi
expect_contains 'the message names setup' "$SHIPPED_OUT" '/retroloop:setup'
expect_eq 'one line, nothing more' "$(printf '%s\n' "$SHIPPED_OUT" | wc -l | tr -d ' ')" '1'
end

# ── A14 · arguments and exit codes pass straight through ─────────────────────
begin A14 'the shipped command passes its arguments and the exit code through'
new_sandbox
shipped_on_path
fake_app_executable "$SB/fake-cli"
run_shipped RETROLOOP_APP="$SB/fake-cli" -- record list --text 'two words' --json
expect_eq 'shipped exit' "$SHIPPED_RC" '0'
expect_contains 'first argument' "$SHIPPED_OUT" 'arg[record]'
expect_contains 'second argument' "$SHIPPED_OUT" 'arg[list]'
expect_contains 'a flag' "$SHIPPED_OUT" 'arg[--text]'
expect_contains 'an argument with a space stays one argument' "$SHIPPED_OUT" 'arg[two words]'
expect_contains 'last argument' "$SHIPPED_OUT" 'arg[--json]'
run_shipped RETROLOOP_APP="$SB/fake-cli" RL_FAKE_EXIT=4 -- review close
expect_eq "the app's exit code comes back" "$SHIPPED_RC" '4'
end

# ── A15 · a user's own retroloop further along PATH still outranks everything ─
# The shipped command sits first on PATH in every session, so asking the shell
# for one answer ("which retroloop?") always returns the shipped one — and a
# guard that only refuses that answer throws the whole rung away, along with a
# user's own `retroloop` a couple of entries later. The rung must be walked.
begin A15 "a user's own retroloop further along PATH is still the answer"
new_sandbox
shipped_on_path
fake_retroloop_on_path
fake_root_checkout "$SB/home/.retroloop"
run_resolver
expect_resolution 'path' "$SB/bin/retroloop"
run_hook
expect_hook "$TRACKED"
run_shipped -- --version
expect_eq 'shipped exit' "$SHIPPED_RC" '0'
expect_contains "the shipped command ran the user's own binary" "$SHIPPED_OUT" '0.0.0-fake'
end

# ── A16 · the marker is missing: refuse, never run forever ───────────────────
# The marker is one dotfile beside the command. A packaging step that drops
# dotfiles (`cp bin/* …`), a half-finished install, someone copying the command
# out — any of those leaves a command whose resolver answers with the command
# itself. Exec'ing that is a process that never ends and never prints: for an
# agent, a shell call that hangs the session. The command must notice and stop.
begin A16 'no marker beside the shipped command — one line, a clean exit, no loop'
new_sandbox
mkdir -p "$SB/plugin/bin" "$SB/plugin/scripts"
cp "$PLUGIN_BIN/retroloop" "$SB/plugin/bin/retroloop"
cp "$RESOLVER" "$SB/plugin/scripts/resolve-cli.sh"
chmod +x "$SB/plugin/bin/retroloop"
SHIPPED_BIN="$SB/plugin/bin"
run_shipped -- --version
expect_eq 'it returned rather than being killed' "$SHIPPED_RC" '127'
expect_contains 'the message says the command resolved to itself' "$SHIPPED_OUT" 'resolved to itself'
expect_contains 'the message says what to do about it' "$SHIPPED_OUT" 'reinstall the plugin'
expect_eq 'one line, nothing more' "$(printf '%s\n' "$SHIPPED_OUT" | wc -l | tr -d ' ')" '1'
end

# ── A11 · the hook's shape, across every case above ──────────────────────────
begin A11 'the hook always prints exactly one line and exits 0'
if [ -n "$SHAPE_VIOLATIONS" ]; then
  CASE_FAILED=1
  DETAIL="$SHAPE_VIOLATIONS"
fi
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=16
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
