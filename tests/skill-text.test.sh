#!/usr/bin/env bash
#
# Acceptance suite — the sentences the shipped `retroloop` command changes in
# the skills (`skills/review/SKILL.md`, `skills/setup/SKILL.md`).
#
#   bash tests/skill-text.test.sh
#
# The review skill used to tell the human that Retroloop was not usable here
# and that the command was not installed — on a machine where setup had put the
# app in place — and then told the agent to stop searching. The plugin now ships
# the command, so that text is wrong and is gone. These checks pin the new
# sentences so nobody writes the old ones back.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REVIEW="$REPO_ROOT/skills/review/SKILL.md"
SETUP="$REPO_ROOT/skills/setup/SKILL.md"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

[ -f "$REVIEW" ] || { printf 'FAIL no review skill at %s\n' "$REVIEW"; exit 1; }
[ -f "$SETUP" ] || { printf 'FAIL no setup skill at %s\n' "$SETUP"; exit 1; }

FLAT_REVIEW="$(tr '\n' ' ' <"$REVIEW" | sed 's/[[:space:]][[:space:]]*/ /g')"
FLAT_SETUP="$(tr '\n' ' ' <"$SETUP" | sed 's/[[:space:]][[:space:]]*/ /g')"

has() { # <name> <haystack> <regex>
  if printf '%s' "$2" | grep -qE -- "$3"; then ok "$1"; else ko "$1" "no match for: $3"; fi
}
lacks() { # <name> <haystack> <regex>
  if printf '%s' "$2" | grep -qE -- "$3"; then ko "$1" "found: $3"; else ok "$1"; fi
}

# ── the review skill: the shipped command is the normal way ──────────────────
has 'the review skill says the plugin ships the command' \
  "$FLAT_REVIEW" 'plugin ships the .retroloop. command'
has 'it says the command is on the search path of every session' \
  "$FLAT_REVIEW" 'search path of every session'
has 'the honest missing-app sentence names setup' \
  "$FLAT_REVIEW" 'Run ./retroloop:setup.'

# ── the review skill: the give-up text and the stop rule are gone ────────────
lacks 'the give-up text is gone' \
  "$FLAT_REVIEW" 'command is not installed and this is not the Retroloop repository'
lacks 'it no longer asks the human to install what they already have' \
  "$FLAT_REVIEW" 'Install it, or tell me where the Retroloop checkout is'
lacks 'Retroloop is no longer called unusable' \
  "$FLAT_REVIEW" 'not usable here'
lacks 'the stop-searching rule is gone' \
  "$FLAT_REVIEW" 'stop searching'

# ── the review skill: the repository fallback survives ───────────────────────
has 'working inside the app checkout is still a way in' \
  "$FLAT_REVIEW" 'bun run --silent retroloop'
has 'the missing-bun branch still says the true thing' \
  "$FLAT_REVIEW" '.bun. is not installed, and the CLI only runs under bun'

# ── the setup skill: it verifies the short command and reports it ────────────
has 'setup verifies the short command the way later sessions call it' \
  "$FLAT_SETUP" 'verify the short command the way every later session calls it'
has 'the checklist reports the short command' \
  "$FLAT_SETUP" 'Short command works'
has 'the checklist says it counts from the next session' \
  "$FLAT_SETUP" 'from the next session'
has 'one permission rule covers every Retroloop call' \
  "$FLAT_SETUP" 'Bash\(retroloop:\*\)'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
