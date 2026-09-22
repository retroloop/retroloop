#!/usr/bin/env bash
#
# Acceptance suite — how the setup skill asks (`skills/setup/SKILL.md`).
#
#   bash tests/setup-questions.test.sh
#
# Two rulings are pinned here.
#
# First: every question setup asks goes through Claude Code's question panel,
# and is written in the file the way the panel shows it — a header chip, the
# question sentence, then its options, the recommended one first and marked
# "(Recommended)", one line of description each. The panel adds a free-text
# choice of its own, so the file never writes one: an option called "something
# else" is that free-text choice under a second name, and leaves the user two
# ways to type one answer. A question the AI cannot honestly recommend an
# answer to says so in the question itself instead of pretending.
#
# The shape of a panel is not ours to choose — these are the `AskUserQuestion`
# tool's own limits, and a file that breaks them is a panel that never draws:
#
#   · between 2 and 4 written options; one option is not a panel, and the
#     free-text choice the panel adds is not one of the written ones, so a
#     second option has to be a real alternative rather than "type your own";
#   · each option label is 1 to 5 words, with "(Recommended)" on top of that
#     and the reasoning in the description line, not the label;
#   · each panel names a header chip of at most 12 characters.
#
# Setup used to pose most of its questions as plain prose, and only a few said
# "through the question tool" — so the user saw a wall of sentences and no
# panel. So the count below is exact rather than a floor, and no line outside a
# panel block may end in a question mark: a question added later has to be
# written as a panel, and counted here on purpose.
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
rule_has 'the rule says only the real choices are written as options' \
  'lists just the real choices'
rule_has 'the rule says a label stays short, and why' \
  'Keep the label short'

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

  if [ "$nopts" -ge 2 ] && [ "$nopts" -le 4 ]; then
    ok "the panel has between two and four written options — $q"
  else
    ko "the panel has between two and four written options — $q" \
      "found $nopts option lines; the tool takes 2 to 4"
  fi

  header="$(awk -v s="$n" 'NR > s { if ($0 !~ /^>/) exit; if ($0 ~ /^> *Header: /) print }' "$SKILL" |
    head -1 | sed -n 's/^> *Header: `\([^`]*\)`.*/\1/p')"
  if [ -n "$header" ] && [ "${#header}" -le 12 ]; then
    ok "the panel names a header chip of at most twelve characters — $q"
  else
    ko "the panel names a header chip of at most twelve characters — $q" \
      "header is \"$header\" (${#header} characters)"
  fi

  freetext="$(printf '%s\n' "$opts" | grep -iE '^> +- \*\*((some|any)(thing|where) else|other)\b' || true)"
  if [ -z "$freetext" ]; then
    ok "no option repeats the free-text choice the panel adds by itself — $q"
  else
    ko "no option repeats the free-text choice the panel adds by itself — $q" "$freetext"
  fi

  long="$(printf '%s\n' "$opts" | sed -n 's/^> *- \*\*\([^*]*\)\*\*.*/\1/p' |
    sed 's/ *(Recommended)//' | awk 'NF < 1 || NF > 5')"
  if [ -z "$long" ]; then
    ok "every option label is one to five words, as the tool takes them — $q"
  else
    ko "every option label is one to five words, as the tool takes them — $q" \
      "not one to five words: $long"
  fi

  if printf '%s' "$first" | grep -q '(Recommended)' ||
    printf '%s' "$q" | grep -qiE 'not sure|unsure|nothing to recommend'; then
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

if [ "$qcount" -eq 9 ]; then
  ok "every question setup asks is written as a panel — nine of them ($qcount found)"
else
  ko "every question setup asks is written as a panel — nine of them ($qcount found)" \
    'the count is exact: a question added or dropped is a deliberate edit to this line'
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
# Opus is the recommended model because every account can run it; Fable is the
# top-tier model and many corporate accounts do not have it, so it stays an
# option and never the default a newcomer lands on.
has 'the model question recommends Opus, first' '\*\*Opus \(Recommended\)\*\*'
has 'and the example file records that same default' \
  'tracking: this tool only model: opus subagent model: opus'
lacks 'nothing in the skill still recommends Fable' 'Fable \(Recommended\)'
has 'the launch-rule question' 'launch rule'

has 'the missing-tools question names what this machine actually lacks' \
  '<the missing tools, named> are missing'
lacks 'the missing-tools question hard-codes no set of tools to copy out' \
  'Bun, unzip and curl are missing'

has 'the no-identity branch is a panel question of its own, written out' \
  'This machine has no git identity set'
has 'and that question says outright that there is nothing to recommend' \
  'nothing to recommend'

n_model="$(grep -c 'claude --model' "$SKILL")"
if [ "$n_model" -eq 1 ]; then
  ok 'what `model:` accepts is said once, where the file is written'
else
  ko 'what `model:` accepts is said once, where the file is written' \
    "said on $n_model lines"
fi

# --- 4 · nothing is asked as prose any more

lacks 'the vague "question tool" phrasing is gone, everywhere' 'question tool'

stray="$(grep -nE '\?\**$' "$SKILL" | grep -vE '^[0-9]+:> \*\*.*\?\*\*$' || true)"
if [ -z "$stray" ]; then
  ok 'no question is posed as prose — every line ending in a question mark is a panel question'
else
  ko 'no question is posed as prose — every line ending in a question mark is a panel question' \
    "$stray"
fi

wide="$(awk '/^```/ { inc = !inc; next } inc { next } NR <= 6 { next } /^>/ { next } length > 88 { printf "line %d is %d characters\n", NR, length }' "$SKILL")"
if [ -z "$wide" ]; then
  ok 'the prose is wrapped to the width the rest of the file uses'
else
  ko 'the prose is wrapped to the width the rest of the file uses' "$wide"
fi

# --- 5 · the remote-backup question, and everything hanging off it, is gone

lacks 'setup never mentions a remote' 'remote'
lacks 'setup never offers a backup' 'backup'
lacks 'the GitHub command is gone' 'gh repo create'
lacks 'the permanent-decline wording is gone' 'that is the answer for good'
lacks 'the once-and-never-again offer is gone' 'once, and never again'
lacks 'the push permission rule that hung on a remote is gone' 'plugin-push'
lacks 'no rule is conditional on having taken a remote' 'took a remote'

declines="$(grep -rniE 'already declined|offered once at setup|the (user|human) declined' "$REPO_ROOT/scripts" || true)"
if [ -z "$declines" ]; then
  ok 'no script says the user was ever asked about a remote, or declined one'
else
  ko 'no script says the user was ever asked about a remote, or declined one' "$declines"
fi

CHECKLIST="$(awk '/^## 7 · The checklist/,0' "$SKILL" | tr '\n' ' ')"
if printf '%s' "$CHECKLIST" | grep -qiE 'remote|backup|push'; then
  ko 'the checklist has no remote line' 'the checklist still mentions a remote'
else
  ok 'the checklist has no remote line'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
