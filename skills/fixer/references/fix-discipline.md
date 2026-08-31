# Fix discipline — how every fix ships

The fixer's job is not to write plausible fixes; it is to ship fixes that
demonstrably remove a failure that demonstrably existed. Four steps, in
order, for every fix:

## 1 · Control-test first

Before authoring anything, reproduce the failure **with the fix absent** (or
unreachable, for a fix that already half-exists). Replay the trigger from the
record's evidence — the same kind of request, the same conditions — and watch
for the failure signature the record describes.

**If the failure does not reproduce, withdraw the fix unbuilt** and say so on
the record. A fix authored over a failure you couldn't reproduce is a fix you
can never verify — you'd be shipping a guess, and the green light afterwards
would be fiction. "It didn't reproduce" is a legitimate, honest outcome; it
usually means the trigger needs more evidence from a future session.

## 2 · Author

Build the selected solution at its approved level — the envelope the human
granted. The record's agreed direction and level are binding; a better idea
at a bigger level goes back to a future retro, not into this fix.

## 3 · Verify — the signature GONE, not lessened

Re-run the same trigger with the fix in place. The failure signature must be
**absent** — not rarer, not milder, not "improved". A fix that lessens a
failure has moved it, and moved failures return. If the signature still
shows, revise once or withdraw honestly; never ship on "better than before".

## 4 · Re-run the original failure verbatim

Last, replay the *exact* original incident from the record — the human's own
request, as it happened — and confirm the outcome is now right. Steps 1 and 3
prove the mechanism; this step proves the case that actually hurt. It catches
the fix that satisfies the abstracted trigger while still failing the real
one.

## Escalation: prose → checklist → hook/script

Fixes start as words and earn their way up:

- **prose** — guidance where the AI already reads (an instruction line, a
  skill sentence);
- **checklist** — a step in a procedure that something walks explicitly;
- **hook/script** — deterministic enforcement that cannot be skipped.

Escalate **only as recurrence proves the weaker form insufficient** — a
second occurrence *after* the prose fix shipped is the argument for the hook,
and it arrives through a new record the human approves, not by the fixer's
initiative. Starting at enforcement for a first occurrence buys rigidity
nothing has earned yet.

## Holistic, and what recurrence means

**A fix targets every logged occurrence of the pattern, not the one that
triggered it.** Before authoring, read the record's related and prior issues;
if three records log the same pattern in three surfaces, one fix covers all
three or it is not the fix — a patch on the newest occurrence leaves the
pattern alive and the ledger lying.

**Recurrence after a fix is evidence the fix was wrong — never a reason to
re-apply it.** If the friction returns, the previous fix failed: say so on
the record, and let the next retro's record name why it failed (wrong root?
wrong layer? guidance where enforcement was needed?) before anything new
ships. Re-applying the same fix harder is the one move this discipline
forbids outright.
