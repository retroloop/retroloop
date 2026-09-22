#!/usr/bin/env bash
#
# Acceptance suite — how the setup skill asks (`skills/setup/SKILL.md`).
#
#   bash tests/setup-questions.test.sh
#
# Two rulings are pinned here.
#
# First: every question setup asks goes through Claude Code's question panel,
# and is written in the file the way the panel shows it — the question
# sentence, then its options, the recommended one first and marked
# "(Recommended)", one line of description each. The panel adds a free-text
# choice of its own, so the file never writes one. A question whose answer the
# AI cannot honestly recommend says it is unsure instead of pretending.
# Setup used to pose most of its questions as plain prose, and only a few said
# "through the question tool" — so the user saw a wall of sentences and no
# panel.
#
# Second: the remote-backup question is gone. It assumed GitHub, and it
# assumed a remote was a one-time chance the user could lose by saying no. A
# remote is the user's own choice, to make whenever they like, so setup does
# not mention one at all — no `gh repo create`, no backup, no permission rule
# that hangs on having taken one, no checklist line.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/skills/setup/SKILL.md"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

[ -f "$SKILL" ] || { printf 'FAIL no skill at %s\n' "$SKILL"; exit 1; }

FLAT="$(tr '\n' ' ' <"$SKILL" | sed 's/[[:space:]][[:space:]]*/ /g')"
has() { if printf '%s' "$FLAT" | grep -qE -- "$2"; then ok "$1"; else ko "$1" "no match for: $2"; fi; }
lacks() { if printf '%s' "$FLAT" | grep -qiE -- "$2"; then ko "$1" "found: $2"; else ok "$1"; fi; }

# --- 1 · the rule, stated once near the top

RULE_ZONE="$(sed -n '1,60p' "$SKILL" | tr '\n' ' ' | sed 's/[[:space:]][[:space:]]*/ /g')"
rule_has() {
  if printf '%s' "$RULE_ZONE" | grep -qE -- "$2"; then ok "$1"; else ko "$1" "no match in the first 60 lines for: $2"; fi
}

rule_has 'the rule is stated near the top, in the skill.s own words' \
  'question goes through the question panel'
rule_has 'the rule names the tool that draws the panel' 'AskUserQuestion'
rule_has 'the panel supplies the free-text choice, so the file never writes one' \
  'free-text'
rule_has 'the recommended option comes first and is marked' \
  '\(Recommended\)'
rule_has 'an unsure question says so instead of inventing a recommendation' \
  'genuinely unsure'

# --- 2 · every question in the file is written the way the panel shows it

qlines="$(grep -nE '^> \*\*.+\?\*\*$' "$SKILL" | cut -d: -f1)"
qcount=0

for n in $qlines; do
  qcount=$((qcount + 1))
  q="$(sed -n "${n}p" "$SKILL" | sed 's/^> \*\*//; s/\*\*$//')"

  start=$((n - 4))
  [ "$start" -lt 1 ] && start=1
  lead="$(sed -n "${start},$((n - 1))p" "$SKILL")"
  if printf '%s' "$lead" | grep -q 'question panel'; then
    ok "the panel is named right above it — $q"
  else
    ko "the panel is named right above it — $q" \
      'no "question panel" in the four lines before the question'
  fi

  opts="$(awk -v s="$n" 'NR > s { if ($0 !~ /^>/) exit; if ($0 ~ /^> +- /) print }' "$SKILL")"
  nopts="$(printf '%s\n' "$opts" | grep -c '^> ' || true)"
  first="$(printf '%s\n' "$opts" | head -1)"

  if [ "$nopts" -ge 2 ]; then
    ok "the options are listed, at least two of them — $q"
  else
    ko "the options are listed, at least two of them — $q" "found $nopts option lines"
  fi

  if printf '%s' "$first" | grep -q '(Recommended)' ||
    printf '%s' "$q" | grep -qi 'not sure\|unsure'; then
    ok "the recommended option is first and marked, or the question says it is unsure — $q"
  else
    ko "the recommended option is first and marked, or the question says it is unsure — $q" \
      "first option is not marked (Recommended): $first"
  fi

  if [ "$nopts" -ge 1 ] && [ "$(printf '%s\n' "$opts" | grep -vc '—' || true)" -eq 0 ]; then
    ok "every option carries one line of description — $q"
  else
    ko "every option carries one line of description — $q" \
      'an option line has no — description'
  fi
done

if [ "$qcount" -ge 8 ]; then
  ok "every question setup asks is written as a panel ($qcount found)"
else
  ko "every question setup asks is written as a panel ($qcount found)" \
    'fewer panel questions than the steps ask for'
fi

# --- 3 · the questions themselves, by name

has 'the missing-tools question' \
  'Shall I look into how to install them on this machine\?'
has 'the install-route question' 'Approve all at once, or one at a time\?'
has 'the script-shell path question' 'Bun'
has 'the git identity question' "name and email"
has 'the shortcut question' 'browse your plugin from\?'
has 'the issue-tracking question' 'Where do you track issues\?'
has 'the model question' 'Which model runs the manager and the tech leads\?'
has 'the launch-rule question' 'launch rule'

has 'the git identity question has nothing to recommend when the machine has no identity' \
  'no recommended option'

# --- 4 · nothing is asked as prose any more

lacks 'the vague "question tool" phrasing is gone, everywhere' 'question tool'

# --- 5 · the remote-backup question, and everything hanging off it, is gone

lacks 'setup never mentions a remote' 'remote'
lacks 'setup never offers a backup' 'backup'
lacks 'the GitHub command is gone' 'gh repo create'
lacks 'the permanent-decline wording is gone' 'that is the answer for good'
lacks 'the once-and-never-again offer is gone' 'once, and never again'
lacks 'the push permission rule that hung on a remote is gone' 'plugin-push'
lacks 'no rule is conditional on having taken a remote' 'took a remote'

CHECKLIST="$(awk '/^## 7 · The checklist/,0' "$SKILL" | tr '\n' ' ')"
if printf '%s' "$CHECKLIST" | grep -qiE 'remote|backup|push'; then
  ko 'the checklist has no remote line' 'the checklist still mentions a remote'
else
  ok 'the checklist has no remote line'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
