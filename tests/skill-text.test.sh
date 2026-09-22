#!/usr/bin/env bash
#
# Acceptance suite — the sentences the shipped `retroloop` command changes in
# the skills (`skills/review/SKILL.md`, `skills/setup/SKILL.md`) and in the
# manager persona (`agents/manager.md`).
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
MANAGER="$REPO_ROOT/agents/manager.md"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

[ -f "$REVIEW" ] || { printf 'FAIL no review skill at %s\n' "$REVIEW"; exit 1; }
[ -f "$SETUP" ] || { printf 'FAIL no setup skill at %s\n' "$SETUP"; exit 1; }
[ -f "$MANAGER" ] || { printf 'FAIL no manager persona at %s\n' "$MANAGER"; exit 1; }

FLAT_REVIEW="$(tr '\n' ' ' <"$REVIEW" | sed 's/[[:space:]][[:space:]]*/ /g')"
FLAT_SETUP="$(tr '\n' ' ' <"$SETUP" | sed 's/[[:space:]][[:space:]]*/ /g')"
FLAT_MANAGER="$(tr '\n' ' ' <"$MANAGER" | sed 's/[[:space:]][[:space:]]*/ /g')"

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

# ── the review skill: the shipped command runs the INSTALLED app ─────────────
# A behaviour change worth saying out loud. Before, an agent standing in the
# app's own checkout with no `retroloop` on PATH ran that checkout's CLI. The
# shipped command is now always on PATH and always runs the installed release,
# so an agent working on the app's own code has to ask for the checkout on
# purpose. Right for filing real retrospectives, surprising for whoever is
# editing the app — so the skill has to say it.
has 'the skill says the shipped command runs the installed app' \
  "$FLAT_REVIEW" 'shipped command always runs the installed app'
has 'it says how to reach the checkout you are standing in on purpose' \
  "$FLAT_REVIEW" 'on the app.s own code'

# ── the review skill: the exit-code sentence counts its own cases ────────────
lacks 'the exit-code sentence no longer says "neither" of three things' \
  "$FLAT_REVIEW" 'Neither is a condition to improvise around'
has 'it covers all three of them' \
  "$FLAT_REVIEW" 'None of those is a condition to improvise around'

# ── the setup skill: it verifies the short command and reports it ────────────
has 'setup verifies the short command the way later sessions call it' \
  "$FLAT_SETUP" 'verify the short command the way every later session calls it'
has 'the checklist reports the short command' \
  "$FLAT_SETUP" 'Short command works'
has 'the checklist says it counts from the next session' \
  "$FLAT_SETUP" 'from the next session'

# ── the manager persona: no long form, no stale cross-reference ──────────────
# The manager is the actor that copied the long form into every worker's prompt
# in the session this change came from, and it points at § 0 of the review
# skill — which no longer describes "worlds" and no longer offers a long form.
lacks 'the manager no longer carries the long form' \
  "$FLAT_MANAGER" 'cd ~/.retroloop/apps/retroloop && bun run'
lacks 'the manager no longer asks which world it is in' \
  "$FLAT_MANAGER" 'which world you are in'
has 'the manager runs the command the plugin ships' \
  "$FLAT_MANAGER" 'the plugin ships the command'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
