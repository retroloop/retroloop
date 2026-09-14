#!/usr/bin/env bash
#
# Acceptance suite — the setup skill's permission consent (`skills/setup/SKILL.md`).
#
#   bash tests/setup-consent.test.sh
#
# The resolve lane's one launch rule ships inside the template's own project
# settings; setup shows it and asks whether to keep it. This suite pins that
# the skill says so, and no longer tells an agent to write that rule into a
# settings file of its own choosing.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/skills/setup/SKILL.md"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

FLAT="$(tr '\n' ' ' <"$SKILL" | sed 's/[[:space:]][[:space:]]*/ /g')"
has() { if printf '%s' "$FLAT" | grep -qE -- "$2"; then ok "$1"; else ko "$1" "no match for: $2"; fi; }
lacks() { if printf '%s' "$FLAT" | grep -qE -- "$2"; then ko "$1" "found: $2"; else ok "$1"; fi; }

[ -f "$SKILL" ] || { printf 'FAIL no skill at %s\n' "$SKILL"; exit 1; }

has 'the launch rule ships with the template, in the plugin'"'"'s own settings' \
  'template carries `.claude/settings.json` inside the plugin'
has 'the rule is named verbatim' 'Bash\(claude --bg:\*\)'
has 'setup asks keep or remove through the question tool' \
  'question tool whether to keep it or remove it'
has 'the rule reaches only sessions running from the plugin' \
  'applies only to sessions whose working directory is the plugin'
has 'workers rely on auto mode in the target repository' \
  'rely on auto mode there'
has 'the launch rule is never written to a local settings file' \
  'never into a local settings file'
has 'the checklist reports the choice' 'Launch rule kept or removed'
has 'the plugin folder must be trusted for the rule to apply' \
  'Ignoring 1 permissions.allow entry'
has 'trust is the human'"'"'s one step, granted in a terminal' \
  'cd ~/.retroloop/plugins/my && claude'
has 'setup never writes the trust entry itself' \
  'do not write the trust entry'
has 'the push rule still needs a remote and consent' \
  'Only if the user took a remote above'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
