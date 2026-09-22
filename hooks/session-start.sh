#!/usr/bin/env bash
# Retroloop SessionStart hook — one line of context, never more.
# Installs nothing, CREATES NOTHING, always exits 0.
#
# The line names the session's notes file. It does not make it: the folder
# appears on the first write, which belongs to the notes skill and to a session
# that actually had friction in it. A hook that mkdir'd here would leave an
# empty folder behind for every session that never needed one.

set -u

# The hook's stdin is Claude Code's event JSON, and `session_id` is the only
# field read from it. The parse is deliberately loose — one field, by name,
# anywhere in the payload — because the field list is not documented and a
# shape change must cost the line its path, never the session its start.
# `[ -t 0 ]` first: a hook run by hand from a terminal has no JSON coming, and
# `cat` on a tty would block a session start forever. A hang is the one failure
# mode worse than a missing path.
input=''
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
# An id is a single path segment or it is not an id: anything with a slash or a
# leading dot is dropped rather than printed as part of a path.
case "$session_id" in
  '' | */* | .*) session_id='' ;;
esac

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

# Two different sentences, because they are two different situations and only
# one of them is answered by running setup. When the app is installed and Bun
# is what cannot be found, setup already succeeded for this person: sending
# them back through it fixes nothing and hides the cause.
if [ "$found" -ne 1 ]; then
  if [ "${RETROLOOP_CLI_MISS:-}" = 'no-bun' ]; then
    echo 'Retroloop is set up, but Bun is missing — install Bun, or set RETROLOOP_BUN to the bun program'
  else
    echo 'Retroloop is installed but not set up — run /retroloop:setup'
  fi
  exit 0
fi

# The root is printed the way the human types it: `~/.retroloop` when nothing
# overrides it, the override verbatim when something does.
if [ -n "${RETROLOOP_HOME:-}" ]; then
  root="$RETROLOOP_HOME"
else
  root='~/.retroloop'
fi

if [ -n "$session_id" ]; then
  echo "This session is tracked by Retroloop: keep friction notes (skill: notes) in $root/sessions/$session_id/notes.md; /retroloop:review when the session winds down."
else
  # No id, no path: a wrong path is worse than none, and the skill can still
  # ask where notes should go.
  echo 'This session is tracked by Retroloop: keep friction notes (skill: notes); /retroloop:review when the session winds down.'
fi

exit 0
