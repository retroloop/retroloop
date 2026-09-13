#!/usr/bin/env bash
#
# Acceptance suite — retrospectives are the human's to open.
#
#   bash tests/human-only-retro.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# A retrospective is a conversation: the human reads the drafts, decides each
# record, and talks back. A background agent that files one while nobody is
# there produces a review no one asked for, and enough of them bury the human
# under retrospectives of retrospectives. So every lane persona must say it
# never files one, and the review skill must say it is the human's to invoke.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

flat() { tr '\n' ' ' <"$1" | sed 's/[[:space:]][[:space:]]*/ /g'; }

has() { # <case> <file> <regex> — the file, flattened, must match the regex
  [ -f "$2" ] || { ko "$1" "no file at $2"; return; }
  if flat "$2" | grep -qE -- "$3"; then ok "$1"; else ko "$1" "no match in $2 for: $3"; fi
}

for persona in manager tech-lead worker reviewer; do
  f="$REPO_ROOT/agents/$persona.md"
  has "$persona: never files a retrospective and never runs the review skill" "$f" \
    '[Nn]ever files? a retrospective'
  has "$persona: retrospectives belong to the human, in human-guided sessions" "$f" \
    'human-guided session'
  has "$persona: a human who wants one for a background session runs it there" "$f" \
    'enters that session and runs the review'
done

SKILL="$REPO_ROOT/skills/review/SKILL.md"
has 'review skill: invoked only by the human, never by an agent on its own' "$SKILL" \
  'invoked only by the human'
has 'review skill: an agent at the CLI must not file for a session no human guides' "$SKILL" \
  'must not file a revision for a session the human is not guiding'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
