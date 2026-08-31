---
name: notes
description: Keep running friction notes during a Retroloop-tracked session. Use the moment something gets in the way — the user sounds frustrated, repeats an instruction, an instruction gets followed wrongly, turns or tool calls or context are wasted, rules contradict each other, or a skill recommends a command that doesn't work. The end-of-session /retroloop:review reads these notes.
---

# notes — write friction down while it is still true

Notes go in one file, `retroloop-notes.md`, in this session's scratchpad
directory (the one named in your system prompt). If this harness names no
scratchpad, ask the user once where session notes should live and use that
path for the rest of the session.

Append an entry the moment friction happens — not at the end, when the details
are gone. Each entry:

```
## <time> — <one-line what happened>
- evidence: what it cost (wasted turns / wasted tool calls / burnt context / a wrong result)
- their words: "<the user's message, verbatim>"   (when frustration is the signal)
- suspect: <the skill, rule, instruction, or gap that caused it — if known>
```

## What counts

**Frustration in the user's own messages is the lead signal** — it requires
the least judgment and sizes how badly something went. Capture their words
exactly as written; the verbatim message is evidence the retro preserves.
From it, work backward: repeated instructions, instructions followed wrongly,
instruction overload.

Also track problems injected into your own context, invisible to the user:
rules that contradict each other, a skill recommending a command that doesn't
work, guidance that burned your attention or context window.

**The gate: no session evidence → not in the notes.** Only things that
actually happened in this session, with what they cost. Never file an
anticipated mistake — Retroloop builds only from things that actually
happened.

These notes are raw material, not conclusions: record what happened, not what
should change. Solutions are `/retroloop:review`'s job, with the user
deciding.
