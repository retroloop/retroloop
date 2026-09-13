#!/usr/bin/env bash
#
# Acceptance suite — releasing a personalization plugin (`scripts/deploy.sh`).
#
#   bash tests/deploy.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# A RELEASE THAT DID NOT LAND MUST NOT LOOK LIKE ONE. The version in the
# manifest is the only signal Claude Code has that a plugin changed, so a
# deploy that bumps and commits but never reaches the running Claude Code is
# indistinguishable — from the outside — from one that worked. Half this suite
# is about that: the update's own answer is checked against the version just
# written, and a disagreement is a loud failure that still tells the human the
# commit is safe.
#
# Every case runs under `env -i` in its own sandbox: a temp HOME carrying a
# .gitconfig (git will not commit without an identity), a real git repository
# for the plugin, sometimes a bare repository beside it to push to, and a stub
# `claude` that answers `plugin update` however the case wants. No real plugin
# is ever updated; the preflight aborts if a real `claude` can be reached from
# the base PATH at all.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="$REPO_ROOT/scripts/deploy.sh"

BASE_PATH='/usr/bin:/bin'

RELOAD_LINE='Plugin released as 0.1.1. In any Claude Code session that is already open, type /reload-plugins once. New sessions need nothing.'
COMMIT_SUBJECT='release 0.1.1 — #r-1 #r-2'
UPDATE_ARGV='plugin|update|my@my-marketplace|--json|-y'

# ── sandboxes ────────────────────────────────────────────────────────────────
SB=''
SANDBOXES=''

new_sandbox() { # [plugin name]
  local name="${1:-my}"
  SB="$(mktemp -d "${TMPDIR:-/tmp}/rl50d-XXXXXX")"
  SANDBOXES="$SANDBOXES $SB"
  mkdir -p "$SB/home" "$SB/bin" "$SB/plugin/.claude-plugin"
  : >"$SB/claude.calls"

  # git refuses to commit without an identity, and under `env -i` the only
  # place it can find one is this HOME.
  cat >"$SB/home/.gitconfig" <<'GITCONFIG'
[user]
	name = Retroloop Test
	email = test@example.invalid
[commit]
	gpgsign = false
GITCONFIG

  cat >"$SB/plugin/.claude-plugin/plugin.json" <<JSON
{
  "name": "$name",
  "description": "A personalization plugin, for one person.",
  "version": "0.1.0"
}
JSON

  git -C "$SB/plugin" init -q
  git -C "$SB/plugin" symbolic-ref HEAD refs/heads/main
  git_here add -A
  git_here commit -qm 'my personalization plugin'
  write_claude_stub
}

# git, run the way the script will run it: no ambient environment at all.
git_here() {
  env -i HOME="$SB/home" PATH="$BASE_PATH" GIT_CONFIG_NOSYSTEM=1 \
    git -C "$SB/plugin" "$@"
}

git_bare() { # <args...> against the sandbox's bare remote
  env -i HOME="$SB/home" PATH="$BASE_PATH" GIT_CONFIG_NOSYSTEM=1 \
    git -C "$SB/remote.git" "$@"
}

add_remote() {
  env -i HOME="$SB/home" PATH="$BASE_PATH" GIT_CONFIG_NOSYSTEM=1 \
    git init -q --bare "$SB/remote.git"
  git_here remote add origin "$SB/remote.git"
}

# The stub answers `plugin update` the way a Claude Code that really updated
# would: with the version now in the plugin's manifest. A case that wants a
# release to go wrong drops a file to override the answer.
write_claude_stub() {
  {
    printf '#!/bin/sh\n'
    printf "SB='%s'\n" "$SB"
    cat <<'STUB'
line=''; sep=''
for a in "$@"; do line="$line$sep$a"; sep='|'; done
printf '%s\n' "$line" >>"$SB/claude.calls"

v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SB/plugin/.claude-plugin/plugin.json" | head -n1)"
[ -f "$SB/force-version" ] && v="$(cat "$SB/force-version")"
o='ok'
[ -f "$SB/force-outcome" ] && o="$(cat "$SB/force-outcome")"
printf '{"outcome":"%s","newVersion":"%s"}\n' "$o" "$v"
exit 0
STUB
  } >"$SB/bin/claude"
  chmod +x "$SB/bin/claude"
}

cleanup() {
  local d
  for d in $SANDBOXES; do
    case "$d" in
      */rl50d-*) rm -rf "$d" ;;
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

# ── probes ───────────────────────────────────────────────────────────────────
OUT=''
ERR=''
RC=0

run_deploy() { # <arg>...
  local errf="$SB/stderr.txt"
  OUT="$(env -i HOME="$SB/home" PATH="$SB/bin:$BASE_PATH" GIT_CONFIG_NOSYSTEM=1 \
    bash "$DEPLOY" "$@" 2>"$errf" </dev/null)"
  RC=$?
  ERR="$(cat "$errf" 2>/dev/null)"
}

manifest_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$SB/plugin/.claude-plugin/plugin.json" | head -n1
}

subject() { # the subject of the plugin repo's newest commit
  git_here log -1 --format='%s' 2>/dev/null
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
  [ -f "$DEPLOY" ] || {
    printf 'ABORT: no script at %s\n' "$DEPLOY" >&2
    exit 2
  }
  PATH="$BASE_PATH" command -v git >/dev/null 2>&1 || {
    printf 'ABORT: no git on the base PATH; this suite needs one.\n' >&2
    exit 2
  }
}
preflight

# ── E1 · the release ─────────────────────────────────────────────────────────
begin E1 'bump, commit, update, and the one line the human acts on'
new_sandbox
run_deploy "$SB/plugin" r-1 r-2
expect_eq 'exit' "$RC" '0'
expect_eq 'stdout' "$OUT" "$RELOAD_LINE"
expect_eq 'the manifest' "$(manifest_version)" '0.1.1'
expect_eq 'the commit subject' "$(subject)" "$COMMIT_SUBJECT"
expect_eq 'the update argv' "$(cat "$SB/claude.calls")" "$UPDATE_ARGV"
end

# ── E2 · with a remote ───────────────────────────────────────────────────────
begin E2 'a remote exists — the release commit is on it afterwards'
new_sandbox
add_remote
run_deploy "$SB/plugin" r-1 r-2
expect_eq 'exit' "$RC" '0'
expect_eq 'the commit on the remote' "$(git_bare log -1 --format='%s' main 2>/dev/null)" "$COMMIT_SUBJECT"
expect_contains 'stdout still has the reload line' "$OUT" "$RELOAD_LINE"
end

# ── E3 · without a remote ────────────────────────────────────────────────────
begin E3 'no remote — nothing is pushed, nothing is said about it, still a release'
new_sandbox
run_deploy "$SB/plugin" r-9
expect_eq 'exit' "$RC" '0'
expect_eq 'stdout' "$OUT" "$RELOAD_LINE"
expect_not_contains 'stdout' "$OUT" 'backed up'
expect_eq 'the commit subject' "$(subject)" 'release 0.1.1 — #r-9'
end

# ── E4 · the update landed somewhere else ────────────────────────────────────
begin E4 'the update reports another version — a failed release, loudly'
new_sandbox
printf '0.0.9\n' >"$SB/force-version"
run_deploy "$SB/plugin" r-1 r-2
expect_eq 'exit' "$RC" '1'
expect_not_contains 'stdout' "$OUT" '/reload-plugins'
expect_contains 'stderr' "$ERR" 'deploy:'
expect_contains 'stderr says the commit survives' "$ERR" 'commit'
expect_eq 'the commit is still there' "$(subject)" "$COMMIT_SUBJECT"
expect_eq 'the manifest' "$(manifest_version)" '0.1.1'
end

# ── E5 · the update did not report ok ────────────────────────────────────────
begin E5 'the update reports an outcome other than ok — a failed release'
new_sandbox
printf 'error\n' >"$SB/force-outcome"
run_deploy "$SB/plugin" r-1
expect_eq 'exit' "$RC" '1'
expect_not_contains 'stdout' "$OUT" '/reload-plugins'
expect_contains 'stderr' "$ERR" 'deploy:'
end

# ── E6 · no record id ────────────────────────────────────────────────────────
begin E6 'no record id — a release has to say what it carries'
new_sandbox
run_deploy "$SB/plugin"
expect_eq 'exit' "$RC" '2'
expect_contains 'stderr' "$ERR" 'Usage:'
expect_eq 'nothing was committed' "$(subject)" 'my personalization plugin'
expect_eq 'the manifest is untouched' "$(manifest_version)" '0.1.0'
expect_eq 'claude was never called' "$(cat "$SB/claude.calls")" ''
end

# ── E7 · the plugin's own name ───────────────────────────────────────────────
begin E7 'the name comes from the manifest, never from the folder'
new_sandbox other
run_deploy "$SB/plugin" r-3
expect_eq 'exit' "$RC" '0'
expect_eq 'the update argv' "$(cat "$SB/claude.calls")" 'plugin|update|other@my-marketplace|--json|-y'
end

# ── E8 · --no-update ─────────────────────────────────────────────────────────
begin E8 '--no-update — bump, commit and push, but no update, and no claim of a release'
new_sandbox
add_remote
run_deploy --no-update "$SB/plugin" r-1 r-2
expect_eq 'exit' "$RC" '0'
expect_eq 'the manifest' "$(manifest_version)" '0.1.1'
expect_eq 'the commit subject' "$(subject)" "$COMMIT_SUBJECT"
expect_eq 'the commit on the remote' "$(git_bare log -1 --format='%s' main 2>/dev/null)" "$COMMIT_SUBJECT"
expect_eq 'no claude call at all' "$(cat "$SB/claude.calls")" ''
expect_contains 'stdout names the skipped command' "$OUT" 'claude plugin update my@my-marketplace --json -y'
expect_contains 'stdout says not released' "$OUT" 'not released'
expect_not_contains 'no reload line' "$OUT" '/reload-plugins'
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
