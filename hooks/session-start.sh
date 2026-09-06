#!/usr/bin/env bash
# Retroloop SessionStart hook — one line of context, never more.
# Installs nothing, changes nothing, always exits 0.

set -u

# Which CLI counts as "set up" is decided in exactly one place, and the finish
# watch sources the same file. This hook used to probe PATH and one hardcoded
# directory, so an app installed anywhere else was invisible to it forever.
_rl_dir="${BASH_SOURCE[0]%/*}"
[ "$_rl_dir" = "${BASH_SOURCE[0]}" ] && _rl_dir='.'
_rl_resolver="$_rl_dir/../scripts/resolve-cli.sh"

found=0
if [ -f "$_rl_resolver" ]; then
  # shellcheck source=../scripts/resolve-cli.sh
  . "$_rl_resolver"
  retroloop_resolve_cli && found=1
fi

if [ "$found" -eq 1 ]; then
  echo 'This session is tracked by Retroloop: keep friction notes (skill: notes); /retroloop:review when the session winds down.'
else
  echo 'Retroloop is installed but not set up — run /retroloop:setup'
fi

exit 0
