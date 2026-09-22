#!/usr/bin/env bash
#
# Acceptance suite — the skills teach the SSH tunnel and offer no network
# address (`skills/setup/SKILL.md`, `skills/review/SKILL.md`).
#
#   bash tests/bind-tunnel.test.sh
#
# The review server only ever listens on the machine it runs on. Neither skill
# may offer the human a network address, a `--bind` flag or a `lanUrl` link,
# and both must name the SSH tunnel as the way in from another computer — in
# both command forms, the plain one and the one for someone who already runs
# Retroloop locally and so needs a different local port.
#
# A note for whoever edits these skills next. The ban on `--bind`, on `LAN` and
# on a wildcard address is a ban on the skills *offering* any of them: the
# checks below look for the bare string anywhere in the file, which is the only
# guard that a reworded reintroduction cannot slip past. If a later change ever
# wants a skill to quote the app's own refusal message back to the agent, write
# the quotation so it does not carry these strings — or narrow the check here
# in the same commit, deliberately, rather than loosening it to make a run go
# green.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_ROOT/skills/setup/SKILL.md"
REVIEW="$REPO_ROOT/skills/review/SKILL.md"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ko() { fail=$((fail + 1)); printf 'FAIL %s\n  %s\n' "$1" "$2"; }

[ -f "$SETUP" ] || { printf 'FAIL no skill at %s\n' "$SETUP"; exit 1; }
[ -f "$REVIEW" ] || { printf 'FAIL no skill at %s\n' "$REVIEW"; exit 1; }

flatten() { tr '\n' ' ' <"$1" | sed 's/[[:space:]][[:space:]]*/ /g'; }
SETUP_FLAT="$(flatten "$SETUP")"
REVIEW_FLAT="$(flatten "$REVIEW")"

has() { if printf '%s' "$3" | grep -qE -- "$2"; then ok "$1"; else ko "$1" "no match for: $2"; fi; }
lacks() { if printf '%s' "$3" | grep -qE -- "$2"; then ko "$1" "found: $2"; else ok "$1"; fi; }

# --- the setup skill ---------------------------------------------------------

has 'setup states the server only ever listens on this machine' \
  'only ever listens on this machine' "$SETUP_FLAT"
lacks 'setup offers no bind flag' '--bind' "$SETUP_FLAT"
lacks 'setup hands over no network link' 'lanUrl' "$SETUP_FLAT"
lacks 'setup never mentions a local network address' '\bLAN\b' "$SETUP_FLAT"
lacks 'setup offers no wildcard address' '0\.0\.0\.0' "$SETUP_FLAT"
has 'setup gives the tunnel command, same port on both ends' \
  'ssh -N -L 24100:127\.0\.0\.1:24100 you@your-server' "$SETUP_FLAT"
has 'setup says to open the forwarded page locally' \
  'http://localhost:24100' "$SETUP_FLAT"
has 'setup gives the second form, a different local port' \
  'ssh -N -L 24101:127\.0\.0\.1:24100 you@your-server' "$SETUP_FLAT"
has 'setup opens that second form on its own local port' \
  'http://localhost:24101' "$SETUP_FLAT"
has 'setup says the tunnel is run from the human'"'"'s own computer' \
  'own computer' "$SETUP_FLAT"

# --- the review skill --------------------------------------------------------

lacks 'review hands over no network link' 'lanUrl' "$REVIEW_FLAT"
lacks 'review offers no bind flag' '--bind' "$REVIEW_FLAT"
lacks 'review never mentions a local network address' '\bLAN\b' "$REVIEW_FLAT"
lacks 'review offers no wildcard address' '0\.0\.0\.0' "$REVIEW_FLAT"
has 'review says the link handed over is always the local one' \
  'always the local link' "$REVIEW_FLAT"
has 'review states the server only ever listens on this machine' \
  'only ever listens on this machine' "$REVIEW_FLAT"
has 'review names the tunnel for a remote machine' \
  'ssh -N -L 24100:127\.0\.0\.1:24100 you@your-server' "$REVIEW_FLAT"
has 'review says to open the forwarded page locally' \
  'http://localhost:24100' "$REVIEW_FLAT"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
