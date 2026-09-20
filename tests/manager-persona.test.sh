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

# ── the retrospective that started the manager is its own ────────────────────
has 'start prompt: the retrospective named as just finished is the manager'"'"'s work' \
  'just finished and is yours'
has 'start prompt: everything finished before it predates the manager' \
  'finished before it predates? (it|you)'
has 'start prompt: the boundary is a retrospective number, not a time' \
  'retrospective number, not (as )?a time'
has 'resume: a resume prompt naming a finished retrospective is new work' \
  'resume prompt.*just finished'

# ── every session the lane starts carries the family prefix ──────────────────
# The persona prints the `claude … --name "…"` lines the manager runs. The human
# reads the same agents view for their own sessions, and `retroloop-` at the
# front of a name is how they tell the lane's from theirs at a glance. So the
# rule is
# pinned, not one string: EVERY `--name "…"` in the persona, however many a
# later rewrite adds, starts with `retroloop-` — and a persona that prints none
# at all fails too, so the case can never pass by having nothing to check.
NAMES="$(grep -oE -- '--name "[^"]*"' "$PERSONA" || true)"
STRAY="$(printf '%s\n' "$NAMES" | grep -vE -- '^--name "retroloop-' | grep . || true)"
if [ -z "$NAMES" ]; then
  ko 'names: every --name the persona prints starts with retroloop-' 'found no --name "…" in the persona at all'
elif [ -n "$STRAY" ]; then
  ko 'names: every --name the persona prints starts with retroloop-' "without the prefix: $(printf '%s' "$STRAY" | tr '\n' ' ')"
else
  ok 'names: every --name the persona prints starts with retroloop-'
fi

# ── the wait is the CLI, not a plugin script ─────────────────────────────────
has 'wait: the manager arms review wait --any through the CLI' \
  'review wait --any --follow --json'
has 'wait: no deadline, re-armed on every exit' \
  'no deadline'
if printf '%s' "$FLAT" | grep -qF -- 'watch-finish.sh --once'; then
  ko 'wait: the persona no longer tells the manager to run watch-finish.sh --once' 'found: watch-finish.sh --once'
else
  ok 'wait: the persona no longer tells the manager to run watch-finish.sh --once'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
