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
# RETRO_HOME, RETROLOOP_APP, WATCH_REVIEW_CLI, RETROLOOP_BUN and BUN_INSTALL
# unset unless the case sets them (the child is started under `env -i`, so
# nothing leaks in from here).
#
# BUN IS PART OF THE ANSWER NOW, so the sandbox has to own every place Bun can
# be found, and the last of those places is a list of fixed system folders that
# no temp directory can hide. Every probe therefore passes
# RETROLOOP_BUN_DIRS — the resolver's own name for that list — pointed at a
# folder inside the sandbox, so a Bun installed on the machine running this
# suite can never answer for one of the cases. The fixed list the product
# actually ships is asserted separately, by reading it out of the script (A20).
# Bun is still never RUN: a candidate is tested for being runnable and nothing
# more.
#
# The app lives in one fixed place under one root: the root is
# `$RETROLOOP_HOME`, else `~/.retroloop`, and the app is `<root>/apps/retroloop`.
# There is no pointer file of any kind, and `RETRO_HOME` is retired — a set
# `RETRO_HOME` must not move the answer by one character (A9).
#
# Four probes, one per surface:
#   run_hook       runs hooks/session-start.sh and captures its one line
#   run_resolver   sources scripts/resolve-cli.sh in a subshell and reports
#                  RETROLOOP_CLI_SOURCE + RETROLOOP_CLI; RL02_REPO_ROOT is the
#                  repo root a caller passes, which is the resolver's last rung
#   run_resolver_strict  the same, under `set -euo pipefail` and called as a
#                  bare command, which is the only way the errexit promise in
#                  the resolver's header can be tested at all
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
# Setup already succeeded for this person; what is missing is Bun, and the line
# says so rather than sending them back to setup.
BUN_MISSING='Retroloop is set up, but Bun is missing — install Bun, or set RETROLOOP_BUN to the bun program'

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
# The sandbox's stand-in for the fixed folders the Bun lookup walks last — the
# Homebrew and system folders. Empty unless a case puts a Bun in it.
BUN_DIRS=''

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl02-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin" "$SB/sys/bin"
  PATH_PREFIX=''
  SHIPPED_BIN="$PLUGIN_BIN"
  BUN_DIRS="$SB/sys/bin"
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
# Put anywhere a case wants one — on PATH, in the home-folder install place, in
# the folder BUN_INSTALL names, in the sandbox's stand-in for the fixed folders.
fake_bun_at() { # <path to the bun program>
  mkdir -p "${1%/*}"
  {
    printf '#!/bin/sh\n'
    printf 'printf "call\\n" >>"%s"\n' "$SB/calls"
    printf 'printf "bun"\n'
    printf 'for a in "$@"; do printf " [%%s]" "$a"; done\n'
    printf 'printf "\\n"\n'
  } >"$1"
  chmod +x "$1"
  : >"$SB/calls"
}

# The one the shell's own lookup finds: a bun on the sandbox's PATH.
fake_bun_on_path() { fake_bun_at "$SB/bin/bun"; }

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
  HOOK_OUT="$(env -i HOME="$SB/home" PATH="$PATH_PREFIX$SB/bin:$BASE_PATH" RETROLOOP_BUN_DIRS="$BUN_DIRS" "$@" bash "$HOOK" 2>/dev/null </dev/null)"
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
# Why a miss was a miss: `none` (no app anywhere) or `no-bun` (an app, and no
# Bun to run it with). The messages a human reads are chosen off this.
RES_MISS=''

run_resolver() { # [VAR=VALUE ...]
  local out
  out="$(env -i HOME="$SB/home" PATH="$PATH_PREFIX$SB/bin:$BASE_PATH" RETROLOOP_BUN_DIRS="$BUN_DIRS" "$@" bash -c '
    set -uo pipefail
    [ -f "$1" ] || exit 3
    . "$1"
    if retroloop_resolve_cli "${RL02_REPO_ROOT:-}"; then
      printf "%s\n" "$RETROLOOP_CLI_SOURCE"
      printf "%s\n" ${RETROLOOP_CLI[@]+"${RETROLOOP_CLI[@]}"}
      exit 0
    fi
    printf "miss:%s\n" "${RETROLOOP_CLI_MISS:-}"
    exit 1
  ' rl02-probe "$RESOLVER" 2>/dev/null)"
  RES_RC=$?
  RES_SOURCE=''
  RES_CLI=''
  RES_MISS=''
  if [ "$RES_RC" -eq 0 ]; then
    RES_SOURCE="$(printf '%s\n' "$out" | sed -n '1p')"
    RES_CLI="$(printf '%s\n' "$out" | sed -n '2,$p' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  elif [ "$RES_RC" -eq 1 ]; then
    RES_MISS="$(printf '%s\n' "$out" | sed -n 's/^miss://p')"
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

# The same resolver, sourced under `set -euo pipefail` and called as a BARE
# command rather than inside an `if`. The distinction is the whole point: a
# call in a condition switches errexit off for everything the function does, so
# it can never see this. The file's header promises the resolver is safe under
# `set -e`; a rung that reads an exit status by letting a command fail breaks
# that promise, and the run then dies where the rung is, with no output at all
# and later rungs never walked.
run_resolver_strict() { # [VAR=VALUE ...]
  local out
  out="$(env -i HOME="$SB/home" PATH="$PATH_PREFIX$SB/bin:$BASE_PATH" RETROLOOP_BUN_DIRS="$BUN_DIRS" "$@" bash -c '
    set -euo pipefail
    [ -f "$1" ] || exit 3
    . "$1"
    retroloop_resolve_cli "${RL02_REPO_ROOT:-}"
    printf "%s\n" "$RETROLOOP_CLI_SOURCE"
    printf "%s\n" ${RETROLOOP_CLI[@]+"${RETROLOOP_CLI[@]}"}
  ' rl02-probe "$RESOLVER" 2>/dev/null)"
  RES_RC=$?
  RES_SOURCE=''
  RES_CLI=''
  RES_MISS=''
  if [ "$RES_RC" -eq 0 ]; then
    RES_SOURCE="$(printf '%s\n' "$out" | sed -n '1p')"
    RES_CLI="$(printf '%s\n' "$out" | sed -n '2,$p' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  fi
}

WHERE_OUT=''

run_where() { # [VAR=VALUE ...]
  # cwd is the sandbox, so the resolver's repo step (git rev-parse) finds
  # nothing and cannot mask the step under test.
  WHERE_OUT="$(cd "$SB" && env -i HOME="$SB/home" PATH="$PATH_PREFIX$SB/bin:$BASE_PATH" RETROLOOP_BUN_DIRS="$BUN_DIRS" "$@" bash "$WATCH" where 2>&1 </dev/null)"
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
    RETROLOOP_BUN_DIRS="$BUN_DIRS" \
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
fake_bun_on_path
run_hook RETROLOOP_APP="$SB/checkout"
expect_hook "$TRACKED"
run_resolver RETROLOOP_APP="$SB/checkout"
expect_resolution 'env' "$SB/bin/bun $SB/checkout/apps/cli/src/bin.ts"
end

# ── A4 · env, file form ──────────────────────────────────────────────────────
begin A4 'RETROLOOP_APP is a .ts CLI entry'
new_sandbox
fake_bun_on_path
run_hook RETROLOOP_APP="$SB/checkout/apps/cli/src/bin.ts"
expect_hook "$TRACKED"
run_resolver RETROLOOP_APP="$SB/checkout/apps/cli/src/bin.ts"
expect_resolution 'env' "$SB/bin/bun $SB/checkout/apps/cli/src/bin.ts"
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
fake_bun_on_path
fake_root_checkout "$SB/home/.retroloop"
run_hook
expect_hook "$TRACKED"
run_resolver
expect_resolution 'default' "$SB/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
end

# ── A8 · the root moves with RETROLOOP_HOME ──────────────────────────────────
begin A8 'RETROLOOP_HOME names the root; the app is <root>/apps/retroloop'
new_sandbox
fake_bun_on_path
fake_root_checkout "$SB/rlhome"
run_hook RETROLOOP_HOME="$SB/rlhome"
expect_hook "$TRACKED"
run_resolver RETROLOOP_HOME="$SB/rlhome"
expect_resolution 'default' "$SB/bin/bun $SB/rlhome/apps/retroloop/apps/cli/src/bin.ts"
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
fake_bun_on_path
fake_root_checkout "$SB/home/.retroloop"
fake_root_checkout "$SB/rthome"
run_resolver RETRO_HOME="$SB/rthome"
expect_resolution 'default' "$SB/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
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
fake_bun_on_path
fake_root_checkout "$SB/home/.retroloop"
run_resolver RETROLOOP_APP="$SB/checkout"
expect_resolution 'env' "$SB/bin/bun $SB/checkout/apps/cli/src/bin.ts"
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
expect_resolution 'default' "$SB/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
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
expect_eq 'the miss says no app was found at all' "$RES_MISS" 'none'
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

# ── A17 · Bun where its own installer puts it, and nowhere else ──────────────
# The bug this suite grew for: Bun's installer writes `~/.bun/bin` into the
# start-up file Debian and Ubuntu stop reading for a script, so a script shell
# asking for `bun` gets nothing while the program sits there in plain sight.
# The lookup goes and reads it, and the answer is the full path.
begin A17 'Bun only in the home-folder install place — the answer carries its full path'
new_sandbox
fake_root_checkout "$SB/home/.retroloop"
fake_bun_at "$SB/home/.bun/bin/bun"
run_resolver
expect_resolution 'default' "$SB/home/.bun/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
run_hook
expect_hook "$TRACKED"
end

# ── A18 · BUN_INSTALL outranks the home-folder place ─────────────────────────
# Bun's installer sets BUN_INSTALL when it is told to install somewhere else,
# so that variable is a statement about where Bun actually is and beats the
# default guess.
begin A18 'BUN_INSTALL names the install folder and wins over ~/.bun'
new_sandbox
fake_root_checkout "$SB/home/.retroloop"
fake_bun_at "$SB/home/.bun/bin/bun"
fake_bun_at "$SB/elsewhere/bin/bun"
run_resolver BUN_INSTALL="$SB/elsewhere"
expect_resolution 'default' "$SB/elsewhere/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
end

# ── A19 · RETROLOOP_BUN outranks everything ──────────────────────────────────
# The escape hatch, for a Bun in a place no list can know. It is a statement
# about this shell, so it beats the shell's own lookup and every folder; and an
# unusable one falls through rather than killing the session start.
begin A19 'RETROLOOP_BUN names Bun outright and wins; an unusable one falls through'
new_sandbox
fake_root_checkout "$SB/home/.retroloop"
fake_bun_on_path
fake_bun_at "$SB/home/.bun/bin/bun"
fake_bun_at "$SB/own/bun"
run_resolver RETROLOOP_BUN="$SB/own/bun"
expect_resolution 'default' "$SB/own/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
run_resolver RETROLOOP_BUN="$SB/no/such/bun"
expect_resolution 'default' "$SB/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
run_hook RETROLOOP_BUN="$SB/no/such/bun"
expect_hook "$TRACKED"
end

# ── A20 · the shell's answer, then the fixed folders ─────────────────────────
# Asking the shell is the cheap rung and it answers with a full path. The last
# rung is the fixed folders — Homebrew's on a Mac and on Linux, and the system
# ones — which no sandbox can move, so the mechanism is proved against the
# sandbox's stand-in and the shipped list is read out of the script itself.
begin A20 "the shell's own answer is a full path; the fixed folders are the last resort"
new_sandbox
fake_root_checkout "$SB/home/.retroloop"
fake_bun_on_path
run_resolver
expect_resolution 'default' "$SB/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"

new_sandbox
fake_root_checkout "$SB/home/.retroloop"
fake_bun_at "$SB/sys/bin/bun"
run_resolver
expect_resolution 'default' "$SB/sys/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"

# The list is walked first hit wins, so its ORDER is part of the contract, not
# just its membership: Homebrew on a Mac, the place a person links a program
# into, Homebrew on Linux, then the system one.
shipped_dirs="$(sed -n 's/^RETROLOOP_BUN_DIRS_DEFAULT=.\(.*\).$/\1/p' "$RESOLVER")"
expect_eq 'the shipped folder list, in order' "$shipped_dirs" \
  '/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/usr/bin'
end

# ── A21 · no Bun anywhere ────────────────────────────────────────────────────
# The app is installed and setup succeeded; Bun is what is missing. Handing
# back the bare word would move the failure somewhere else and blame Retroloop
# for it, so the resolver stops, says which of the two is missing, and every
# message a human reads names Bun instead of sending them back to setup.
begin A21 'no Bun anywhere — a miss of its own, and every message names Bun'
new_sandbox
fake_root_checkout "$SB/home/.retroloop"
run_resolver
expect_resolver_miss
expect_eq 'the miss says Bun is what is missing' "$RES_MISS" 'no-bun'
run_hook
expect_hook "$BUN_MISSING"
run_where
expect_contains 'where names Bun' "$WHERE_OUT" 'Bun is missing'
expect_not_contains 'where does not send them back to setup' "$WHERE_OUT" '/retroloop:setup'
run_shipped -- --version
expect_eq 'the shipped command stops rather than running a word' "$SHIPPED_RC" '127'
expect_contains 'the shipped command names Bun' "$SHIPPED_OUT" 'Bun is missing'
expect_contains 'and names the escape hatch' "$SHIPPED_OUT" 'RETROLOOP_BUN'
end

# ── A22 · an app the variable names, and no Bun ──────────────────────────────
# The hint reads three ways and now answers three ways: a command, nothing
# here, or — this case — a real app checkout that cannot be run because there
# is no Bun anywhere. It is the arm that decides which sentence a human gets,
# and "set but unusable" would be the wrong one: the variable is right, the app
# is there, and Bun is what is hiding.
begin A22 'RETROLOOP_APP names a real checkout and no Bun exists — the miss names Bun'
new_sandbox
run_resolver RETROLOOP_APP="$SB/checkout"
expect_resolver_miss
expect_eq 'the miss says Bun is what is missing' "$RES_MISS" 'no-bun'
run_hook RETROLOOP_APP="$SB/checkout"
expect_hook "$BUN_MISSING"
run_where RETROLOOP_APP="$SB/checkout"
expect_contains 'where calls it an app with no Bun' "$WHERE_OUT" \
  "RETROLOOP_APP:    $SB/checkout  (an app checkout, and no Bun to run it)"
expect_not_contains 'where does not call the variable unusable' "$WHERE_OUT" 'set but unusable'
# The .ts reading of the same variable answers the same way.
run_resolver RETROLOOP_APP="$SB/checkout/apps/cli/src/bin.ts"
expect_resolver_miss
expect_eq 'the miss says Bun is what is missing' "$RES_MISS" 'no-bun'
end

# ── A23 · the repo rung, with Bun and without ────────────────────────────────
# The last rung: a caller that knows its own checkout passes it in (the finish
# watch does). It runs a .ts file like the two rungs above it, so it has the
# same two outcomes, and the no-Bun one has to be told apart there too.
begin A23 "a caller's own repo checkout — resolved with Bun, a Bun miss without"
new_sandbox
fake_bun_on_path
run_resolver RL02_REPO_ROOT="$SB/checkout"
expect_resolution 'repo' "$SB/bin/bun $SB/checkout/apps/cli/src/bin.ts"

new_sandbox
run_resolver RL02_REPO_ROOT="$SB/checkout"
expect_resolver_miss
expect_eq 'the miss says Bun is what is missing' "$RES_MISS" 'no-bun'
end

# ── A24 · safe under `set -e`, called bare ───────────────────────────────────
# The resolver's header promises it is safe under `set -e`. A rung that reads
# an exit status by letting a command fail keeps that promise only as long as
# every caller happens to call it inside an `if` — and then the walk stops at
# the first unrunnable answer instead of going on to the next rung. Here the
# variable names an app with no Bun and the older spelling names a whole
# command, which needs no Bun at all: the second must still be the answer.
begin A24 'sourced under `set -e` and called bare — an app with no Bun does not end the walk'
new_sandbox
run_resolver_strict RETROLOOP_APP="$SB/checkout" WATCH_REVIEW_CLI='own-cli --wait'
expect_resolution 'env' 'own-cli --wait'
# And an ordinary resolution is unchanged under the same strictness.
new_sandbox
fake_bun_on_path
fake_root_checkout "$SB/home/.retroloop"
run_resolver_strict
expect_resolution 'default' "$SB/bin/bun $SB/home/.retroloop/apps/retroloop/apps/cli/src/bin.ts"
end

# ── A11 · the hook's shape, across every case above ──────────────────────────
begin A11 'the hook always prints exactly one line and exits 0'
if [ -n "$SHAPE_VIOLATIONS" ]; then
  CASE_FAILED=1
  DETAIL="$SHAPE_VIOLATIONS"
fi
end

# ── verdict ──────────────────────────────────────────────────────────────────
total=24
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
