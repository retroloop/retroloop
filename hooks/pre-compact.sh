#!/usr/bin/env bash
# Retroloop PreCompact hook — friction evidence must outlive compaction.
# Copies this session's notes.md to a timestamped snapshot beside it.
# Always exits 0; compaction is never blocked.

set -u

# Same loose, by-name parse as the SessionStart hook, for the same reason: the
# hook payload's field list is not documented, and a shape change must cost a
# snapshot, never the compaction.
# `[ -t 0 ]` first: run by hand from a terminal there is no JSON coming, and
# `cat` on a tty would block compaction indefinitely.
input=''
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
case "$session_id" in
  '' | */* | .*) exit 0 ;;
esac

# One root, one folder per session. The notes file is the notes skill's; this
# hook only ever reads it.
root="${RETROLOOP_HOME:-${HOME:-}/.retroloop}"
notes="$root/sessions/$session_id/notes.md"
[ -f "$notes" ] || exit 0

# `snapshots/` is created HERE and only here — when there is something to put
# in it. A session with no notes leaves no trace of this hook having run.
snapshots="$root/sessions/$session_id/snapshots"
dest="$snapshots/$(date +%Y%m%d-%H%M%S).md"
mkdir -p "$snapshots" 2>/dev/null && cp "$notes" "$dest" 2>/dev/null &&
  echo "Retroloop: friction notes snapshotted to $dest — they survive this compaction; keep appending to $notes."

exit 0
