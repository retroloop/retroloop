#!/usr/bin/env bash
#
# Acceptance suite — the manager persona (`agents/manager.md`).
#
#   bash tests/manager-persona.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# The persona is prose, so what this suite pins is that the rules a manager
# must carry are actually written in it. The one that matters most: a store
# that existed before the manager did may hold dozens of approved, unresolved
# records from earlier retrospectives, and a manager that treats them as its
# queue works through months of someone else's history on its first morning.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PERSONA="$REPO_ROOT/agents/manager.md"

pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

# The persona wraps its prose at 80 columns, so a rule can straddle a line
# break; every check runs against the text flattened onto one line.
FLAT="$(tr '\n' ' ' <"$PERSONA" | sed 's/[[:space:]][[:space:]]*/ /g')"

has() { # <case> <regex> — the persona, flattened, must match the regex
  if printf '%s' "$FLAT" | grep -qE -- "$2"; then ok "$1"; else ko "$1" "no match for: $2"; fi
}

[ -f "$PERSONA" ] || { printf 'FAIL no persona at %s\n' "$PERSONA"; exit 1; }

# ── what predates the manager is not its work ────────────────────────────────
has 'first start: the persona names retrospectives that predate the manager' \
  'predates? (it|you)'
has 'first start: the baseline is taken from review list --finished at the first start' \
  'first start.*review list --finished|review list --finished.*first start'
has 'first start: the baseline is written in the notes, in words' \
  'predate.*notes|notes.*predate'
has 'first start: from then on only later finishes are taken' \
  'finish(es|ed)? after'

# ── the human can hand over an older record ──────────────────────────────────
has 'handover: the human hands an older record over in the manager session' \
  'hand (it |you )?(an )?older record|hands? .*older record'
has 'handover: the manager claims exactly that record' \
  'claims? exactly that record'
has 'handover: the handover is written in the notes' \
  'handover.*notes|notes.*handover'

# ── the reconcile step and the checklist honour the baseline ─────────────────
has 'reconcile: new work excludes what predates the manager' \
  'never mentioned.*predate|predate.*never mentioned'
has 'checklist: an unresolved record may belong to a retrospective that predates the manager' \
  '- \[ \] Every unresolved approved record[^[]*predates you'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
