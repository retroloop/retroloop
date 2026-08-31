#!/usr/bin/env bash
# Retroloop PreCompact hook — friction evidence must outlive compaction.
# Copies the session's retroloop-notes.md (if any) to a durable home.
# Always exits 0; compaction is never blocked.

set -u

input="$(cat 2>/dev/null || true)"
session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -n "$session_id" ] || session_id="unknown-session"

# The notes skill writes to the session scratchpad; find it by session id.
notes=""
for f in "${TMPDIR:-/tmp}"/claude-*/*/"$session_id"/scratchpad/retroloop-notes.md \
  /tmp/claude-*/*/"$session_id"/scratchpad/retroloop-notes.md; do
  [ -f "$f" ] && notes="$f" && break
done

if [ -n "$notes" ]; then
  dest="$HOME/.ai-team/retroloop/notes/${session_id}-$(date +%Y%m%d-%H%M%S).md"
  mkdir -p "$HOME/.ai-team/retroloop/notes" && cp "$notes" "$dest" 2>/dev/null &&
    echo "Retroloop: friction notes preserved at $dest — they survive this compaction; keep appending to the scratchpad copy."
fi

exit 0
