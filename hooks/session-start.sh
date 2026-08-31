#!/usr/bin/env bash
# Retroloop SessionStart hook — one line of context, never more.
# Installs nothing, changes nothing, always exits 0.

set -u

found=0
if command -v retroloop >/dev/null 2>&1; then
  found=1
elif [ -f "$HOME/Developer/retroloop-app/apps/cli/src/bin.ts" ]; then
  found=1
fi

if [ "$found" -eq 1 ]; then
  echo 'This session is tracked by Retroloop: keep friction notes (skill: notes); /retroloop:review when the session winds down.'
else
  echo 'Retroloop is installed but not set up — run /retroloop:setup'
fi

exit 0
