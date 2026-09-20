#!/usr/bin/env bash
#
# Acceptance suite — how the review skill drafts (`skills/review/`).
#
#   bash tests/review-drafting.test.sh
#
# Exit 0 = every case passed. Non-zero = at least one failed, named on its own
# FAIL line with the mismatch under it.
#
# Drafting a retrospective is not one agent typing. The root cause of a
# friction lives in the session that produced it — the commands, the outputs,
# the rules the agent was running under — and only an agent holding that whole
# session can re-derive it. So the main agent nominates and groups, one FORK
# per group does the root-cause work in parallel, and the main agent assembles
# and files. This suite pins the parts of that flow a later edit could quietly
# drop: the group cap, the fork wording and the reason for it, the brief and
# the contract the forks are handed, the diagnostic data every record carries,
# the text-search history lookup that replaced a grep over the exports, and the
# compaction statement.
#
# It also pins the finish wait's default — one persistent monitor, no timeout —
# because that text and `scripts/watch-review.sh` have to say the same thing.
#
# Everything here is prose, so every check runs against the file flattened onto
# one line: the skill wraps at 80 columns and a rule can straddle a break.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SKILL="$REPO_ROOT/skills/review/SKILL.md"
DRAFTER="$REPO_ROOT/skills/review/references/drafter-contract.md"
DIAGNOSTIC="$REPO_ROOT/skills/review/references/diagnostic-data.md"
FIVE_WHYS="$REPO_ROOT/skills/review/references/five-whys.md"
TECH_LEAD="$REPO_ROOT/agents/tech-lead.md"

pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

flat() { tr '\n' ' ' <"$1" | sed 's/[[:space:]][[:space:]]*/ /g'; }

has() { # <case> <file> <regex> — the file, flattened, must match
  [ -f "$2" ] || { ko "$1" "no file at $2"; return; }
  if flat "$2" | grep -qE -- "$3"; then ok "$1"; else ko "$1" "no match in $2 for: $3"; fi
}

hasf() { # <case> <file> <literal> — the file, flattened, must contain it
  [ -f "$2" ] || { ko "$1" "no file at $2"; return; }
  if flat "$2" | grep -qF -- "$3"; then ok "$1"; else ko "$1" "not found in $2: $3"; fi
}

lacksf() { # <case> <file> <literal> — the file must NOT contain it, anywhere
  [ -f "$2" ] || { ko "$1" "no file at $2"; return; }
  if flat "$2" | grep -qF -- "$3"; then ko "$1" "still present in $2: $3"; else ok "$1"; fi
}

lacks() { # <case> <file> <regex> — the file must NOT match
  [ -f "$2" ] || { ko "$1" "no file at $2"; return; }
  if flat "$2" | grep -qEi -- "$3"; then ko "$1" "still matches in $2: $3"; else ok "$1"; fi
}

exists() { # <case> <file>
  if [ -f "$2" ]; then ok "$1"; else ko "$1" "no file at $2"; fi
}

# ── nominate and group ───────────────────────────────────────────────────────
has 'nominate: the records come from the notes and from what the agent remembers' "$SKILL" \
  'nominate.*(notes|remember)'
has 'nominate: a dropped near-duplicate keeps a one-line reason' "$SKILL" \
  'one-line reason'
has 'group: at most three frictions in a group' "$SKILL" \
  '[Aa]t most three frictions'
has 'group: a friction with no sibling is its own group' "$SKILL" \
  'no sibling is its own group'
has 'group: the grouping key is a shared suspected cause or the same surface' "$SKILL" \
  'suspected cause or the same surface'

# ── the forks ────────────────────────────────────────────────────────────────
hasf 'fork: they are forks of the main agent, not fresh agents' "$SKILL" \
  'forks of the main agent'
has 'fork: a fork inherits the whole conversation context, on the same model' "$SKILL" \
  'inherits? (its|the) whole conversation context'
has 'fork: the reason — no tool lets a fresh agent read the session transcript' "$SKILL" \
  'read the session.s transcript'
hasf 'fork: in Claude Code that is the Agent tool with subagent_type fork' "$SKILL" \
  'subagent_type'
has 'fork: one call per group in the same message, so they run in parallel' "$SKILL" \
  'same message.*parallel|parallel.*same message'
has 'fork: each fork writes to agents/draft-<group>/records.json' "$SKILL" \
  'agents/draft-<group>/records.json'
has 'fork: the main agent never files with a fork missing' "$SKILL" \
  'never files? with a fork missing'
has 'fork: on a validation refusal the draft is fixed by hand, never re-forked' "$SKILL" \
  'no automatic re-fork'
has 'after drafting: wait, rounds and close stay the main agent.s' "$SKILL" \
  'wait, the rounds and the close'

# ── the brief and the fork contract ──────────────────────────────────────────
exists 'reference: skills/review/references/drafter-contract.md exists' "$DRAFTER"
hasf 'drafter-contract: the brief template opens with the Group line' "$DRAFTER" \
  'Group: <the shared suspected cause or surface in one line'
hasf 'drafter-contract: the fork contract opens by naming the fork' "$DRAFTER" \
  'You are a fork of the main agent, drafting the records of one group'
has 'drafter-contract: it holds both, under their own headings' "$DRAFTER" \
  '## The brief.*## The fork contract'
hasf 'drafter-contract: the brief carries the notes own suspect line' "$DRAFTER" \
  "the notes' suspect"
hasf 'drafter-contract: the brief carries the human words verbatim' "$DRAFTER" \
  'Your words in the notes, verbatim'
has 'drafter-contract: the brief carries the compaction count' "$DRAFTER" \
  'Compaction: this session compacted <N> times before drafting'
has 'drafter-contract: a fork files nothing and spawns nobody' "$DRAFTER" \
  '[Dd]o not file a revision'
hasf 'SKILL.md points at the drafter contract' "$SKILL" \
  'references/drafter-contract.md'

# ── the diagnostic data ──────────────────────────────────────────────────────
exists 'reference: skills/review/references/diagnostic-data.md exists' "$DIAGNOSTIC"
hasf 'revision file: the record field is diagnosticData' "$SKILL" \
  'diagnosticData'
has 'revision file: diagnosticData is required and must not be empty' "$SKILL" \
  'diagnosticData.*(required|never empty|must not be empty)'
hasf 'revision file: the whole-record example carries diagnosticData' "$SKILL" \
  '"diagnosticData":'
has 'diagnostic-data: it has a skeleton heading' "$DIAGNOSTIC" \
  '## The skeleton'
has 'diagnostic-data: it says what it is for, in neutral words' "$DIAGNOSTIC" \
  '## Why it is there'
has 'diagnostic-data: it carries a worked example' "$DIAGNOSTIC" \
  '## A worked example'
has 'diagnostic-data: every heading carries none when it is empty' "$DIAGNOSTIC" \
  'none.*when.*empty|when.*empty.*none'
hasf 'SKILL.md points at the diagnostic-data reference' "$SKILL" \
  'references/diagnostic-data.md'

for heading in \
  'commands and outputs' \
  'error text' \
  'paths and line references' \
  'commits and versions' \
  'what was tried' \
  'quotes relied on' \
  'candidate earlier records (by text search, not verified)' \
  'limits of this evidence'; do
  hasf "skeleton in SKILL.md: $heading" "$SKILL" "$heading"
  hasf "skeleton in diagnostic-data.md: $heading" "$DIAGNOSTIC" "$heading"
done
hasf 'skeleton in SKILL.md: environment (model, permission mode, plugin versions)' "$SKILL" \
  'model, permission mode, plugin versions'
hasf 'skeleton in diagnostic-data.md: environment (model, permission mode, plugin versions)' "$DIAGNOSTIC" \
  'model, permission mode, plugin versions'

# ── the history lookup ───────────────────────────────────────────────────────
hasf 'history: candidates come from record list --all --text, one query per friction' "$SKILL" \
  'retroloop record list --all --text'
has 'history: one read query per friction' "$SKILL" \
  'one read query per friction'
hasf 'history: they live under the diagnostic-data heading and nowhere else' "$SKILL" \
  'and nowhere else'
has 'history: the recurrence judgment belongs to the resolver' "$SKILL" \
  'recurrence.*resolver|resolver.*recurrence'
has 'history: no draft ever claims "this recurred"' "$SKILL" \
  'never say .this recurred.'
lacksf 'history: the grep over the prior exports is gone' "$SKILL" \
  'retros/*/retro.json'
has 'history: the lesson of patching instance after instance is kept' "$SKILL" \
  'lesson that put a history step here has not changed'

# ── the candidate search: up to three word choices ───────────────────────────
# One query finds the known earlier record in 3 of 10 known recurrences; three
# word choices find it in 9 of 10. A generic word finds everything, which is the
# same as finding nothing — "lead" matched 85 records. So the fallback is part
# of the instruction, in every place the instruction is given.
for f in "$SKILL" "$DRAFTER" "$FIVE_WHYS"; do
  b="$(basename "$f")"
  has "search/$b: up to three word choices" "$f" \
    '[Uu]p to three word choices'
  has "search/$b: single distinctive words before a two-word phrase" "$f" \
    'single distinctive words'
  has "search/$b: the fallback ends in a two-word phrase" "$f" \
    'two-word phrase'
  hasf "search/$b: never generic words, by name" "$f" \
    'lead, test, review, agent'
  has "search/$b: at most the ten most plausible by title" "$f" \
    'ten most plausible by title'
  has "search/$b: say which query found them" "$f" \
    'which query found'
  has "search/$b: the queries and their counts go in the diagnostic data" "$f" \
    '[Ee]very query.*row count'
done
hasf 'search: what the text actually matches, all four fields' "$SKILL" \
  'case-insensitive substring over the title, the slug, the problem and the root cause'
has 'search: the evidence for three tries rather than one' "$SKILL" \
  '3 of 10|three of ten'
hasf 'diagnostic-data: the heading holds the queries too' "$DIAGNOSTIC" \
  'which query found'

# ── the compaction statement ─────────────────────────────────────────────────
hasf 'compaction: the plain line, verbatim' "$SKILL" \
  'This session compacted <N> times before drafting'
has 'compaction: N is the number of files in the snapshots folder' "$SKILL" \
  'number of files in .*snapshots'
has 'compaction: a drafter says where evidence predates a compaction' "$DRAFTER" \
  'predates a compaction'
for f in "$SKILL" "$DRAFTER" "$DIAGNOSTIC" "$FIVE_WHYS" \
  "$REPO_ROOT/skills/review/references/solution-levels.md"; do
  lacks "no \"budget\" anywhere in the skill: $(basename "$f")" "$f" 'budget'
done

# ── the drafter rules in five-whys.md ────────────────────────────────────────
has 'five-whys: the guidance the agent ran under is evidence' "$FIVE_WHYS" \
  'guidance you ran under is evidence'
has 'five-whys: a cause in guidance names the file' "$FIVE_WHYS" \
  '[Nn]ame the file'
has 'five-whys: it names the plugin version from the skill.s base directory path' "$FIVE_WHYS" \
  "base directory path"
has 'five-whys: it quotes the line' "$FIVE_WHYS" \
  'quote it'
has 'five-whys: the human is quoted verbatim, garbles included' "$FIVE_WHYS" \
  'garbles included'
has 'five-whys: the cleaned twin fixes dictation only' "$FIVE_WHYS" \
  'cleaned twin fixes dictation only'
hasf 'five-whys: every solution.s first bullet is scoped to this session' "$FIVE_WHYS" \
  '(derived from this session only)'
hasf 'SKILL.md carries the same scope line' "$SKILL" \
  '(derived from this session only)'

# ── the tech lead starts from the diagnostic data ────────────────────────────
has 'tech-lead: reads the record with record get before any work' "$TECH_LEAD" \
  'record get'
has 'tech-lead: starts from the record.s diagnostic data' "$TECH_LEAD" \
  'diagnostic data'
has 'tech-lead: re-derives the cause from that evidence' "$TECH_LEAD" \
  '[Rr]e-derive the cause'
has 'tech-lead: candidate earlier records are candidates, never a recurrence' "$TECH_LEAD" \
  'never as established recurrence|not as established recurrence'
has 'tech-lead: wrong or thin diagnostic data goes in the report' "$TECH_LEAD" \
  'wrong or thin'

# ── the finish wait: one persistent monitor ──────────────────────────────────
has 'wait: the default for a human-guided session is one persistent monitor' "$SKILL" \
  'persistent monitor'
hasf 'wait: the Monitor tool, with persistent true' "$SKILL" \
  'persistent: true'
hasf 'wait: the description names the retro' "$SKILL" \
  'Retroloop finish watch, retro'
has 'wait: the command is watch-review.sh with the retro id and no timeout' "$SKILL" \
  'scripts/watch-review.sh.*<retroId>'
has 'wait: the script waits with no timeout, prints one line and exits' "$SKILL" \
  'exactly one line'
hasf 'wait: a review closed under an armed watch is stopped with TaskStop' "$SKILL" \
  'TaskStop'
has 'wait: a monitor is never restored after a session restart' "$SKILL" \
  'never restored after a session restart'
has 'wait: whether a monitor survives a compaction is unproven' "$SKILL" \
  'unproven'
has 'wait: re-arm after any compaction the agent can detect' "$SKILL" \
  're-arms? after (any|a) compaction'
has 'wait: the background-task rung stays as the documented fallback' "$SKILL" \
  'fallback for a harness (with|that has) no Monitor'
has 'wait: a printed line DOES wake a session through a monitor' "$SKILL" \
  'every stdout line.*event|line it prints.*event'
lacks 'wait: the claim that a printed line never wakes a session is gone' "$SKILL" \
  'never when it prints a line'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
