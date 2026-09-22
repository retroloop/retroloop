#!/usr/bin/env bash
#
# Acceptance suite — setup's prerequisite step (`skills/setup/SKILL.md`) and the
# prerequisite line on the plugin's front page (`README.md`).
#
#   bash tests/setup-prereq.test.sh
#
# Setup used to check bun and git, refuse to install either, and print one fixed
# curl line as the cure — a line that itself fails on a minimal Linux image for
# want of unzip. These cases pin the replacement: check all four tools setup's
# own commands need, say what is missing, ask only whether to look into it, work
# out what kind of machine this is before proposing anything, propose one route
# with an approve-all-or-one-at-a-time choice, and stop cleanly with an ask-IT
# list when the machine's rules forbid the install. Plus the two lines that
# follow from it: Bun called by its full path after a mid-run install (including
# the check that a script shell can find it), and the review page built right
# after the app's dependencies.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/skills/setup/SKILL.md"
README="$REPO_ROOT/README.md"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

flatten() { tr '\n' ' ' <"$1" | sed 's/[[:space:]][[:space:]]*/ /g'; }

FLAT="$(flatten "$SKILL")"
READMEFLAT="$(flatten "$README")"

has() { if printf '%s' "$FLAT" | grep -qE -- "$2"; then ok "$1"; else ko "$1" "no match for: $2"; fi; }
lacks() { if printf '%s' "$FLAT" | grep -qE -- "$2"; then ko "$1" "found: $2"; else ok "$1"; fi; }
readme_has() { if printf '%s' "$READMEFLAT" | grep -qE -- "$2"; then ok "$1"; else ko "$1" "no match for: $2"; fi; }

[ -f "$SKILL" ] || { printf 'FAIL no skill at %s\n' "$SKILL"; exit 1; }
[ -f "$README" ] || { printf 'FAIL no readme at %s\n' "$README"; exit 1; }

# --- 1 · everything setup's own commands need is checked, before anything changes

has 'the step checks all four tools in one pass' \
  'bun --version git --version unzip -v curl --version'
has 'all four are named as what setup itself needs' \
  'Setup needs four tools'
has 'the check happens before anything is touched' \
  'Check all four before touching anything'
has 'the step only looks, so setup is safe to run again' \
  'This step only looks'
has 'nothing missing is said plainly and nothing is asked' \
  'Everything is already present\. Nothing to install\.'

# --- 2 · say what is missing, ask only whether to look into it

has 'the first question is only whether to look into it' \
  'Shall I look into how to install them on this machine\?'
has 'nothing is proposed before that answer' \
  'Do not propose a command yet'
lacks 'the old refusal to install is gone' \
  'Do not install either yourself'
lacks 'the old fixed cure — one curl line and a fresh terminal — is gone' \
  'open a fresh terminal'

# --- 3 · understand the machine before proposing anything

has 'the machine is understood only after the yes' \
  'Only after that yes, work out where you are'
has 'the package manager is established, not assumed' \
  'package manager that is actually present'
has 'usable elevation is established without a blocking prompt' \
  'Never run a command that can block on a password prompt'
has 'the corporate or managed machine is named' \
  'corporate or managed machine'
has 'the managed signals are named' \
  'no administrator rights, a company proxy or an internal package mirror'
has 'device management is a signal too' 'device-management software'
has 'instructions already loaded in the session are an input' \
  'already loaded in this session that says how software is installed here'
has 'a project instruction file counts' 'CLAUDE\.md'
has 'loaded instructions beat the skill.s own defaults' \
  'win over anything you would otherwise choose'
has 'the managed-machine wording is shown' \
  'This looks like a managed machine'

# --- 4 · one route, with the two ways to approve it

has 'exactly one route is proposed, not a menu' \
  'one. proposal — the route that fits this machine, not'
has 'the route is the exact commands, in order' \
  'exact commands in the order they run'
has 'the choice is approve-all or one-at-a-time' \
  'Approve all at once, or one at a time\?'
has 'approve-all runs them and re-checks' 'then re-check the four tools'
has 'one-at-a-time stops for a yes before each' \
  'stop for a yes before each command'
has 'nothing runs that was not shown first' \
  'nothing runs that was not shown first'

# --- 5 · a blocked machine stops cleanly, as a checklist

has 'a blocked machine is never worked around' \
  'do not improvise around it'
has 'the ask-IT list is printed' 'Ask IT for'
has 'the ask-IT list carries names, reasons and the admin command' \
  'the tools by name, why each is needed, and the command an administrator would run'
has 'the same block answers a plain no' \
  'what you print on a plain .no.'
has 'setup can be run again and picks up where it left off' \
  'running it again picks up from what is actually on the machine'

# --- 6 · Bun installed mid-run is called by its full path (item 3's one sentence)

has 'a mid-run Bun install does not put bun on the path' \
  'does not make the word `bun` work mid-run'
has 'the rest of the run calls Bun by its full installed location' \
  'BUN_INSTALL:-\$HOME/\.bun\}/bin/bun'
has 'a script shell is checked for Bun too' \
  'non-interactive'
has 'the script-shell check is a command, not a hope' \
  "bash -c 'command -v bun'"
has 'a script shell that cannot find Bun is fixed to fit this machine' \
  'fix it in the way that fits this machine'
has 'the reason is that hooks and watch scripts run in that shell' \
  'hooks and watch scripts run in exactly that kind of shell'

# --- 7 · the review page is built after the app's dependencies (item 4, option A)

has 'the review page is built right after the dependencies' \
  "bun run --filter '@retro/web' build"
has 'the build is explained by the dead link it prevents' \
  '503'

# --- 8 · the front page's prerequisite line matches what setup now does

readme_has 'the front page names unzip and curl among the prerequisites' \
  '`unzip` and `curl`'
readme_has 'the front page says setup checks and offers to install on a yes' \
  'only on your yes'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
