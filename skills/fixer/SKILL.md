---
name: fixer
description: The Retroloop fixer — runs in a second terminal, waits for the human to finish the retro review, then implements the approved fixes in the user's personalization plugin and deploys them.
disable-model-invocation: true
argument-hint: "<retro id>"
---

# /retroloop:fixer — the solving side (v1)

This is v1 of Retroloop's solving side: one session, in a second terminal,
that turns an aligned retro into shipped fixes. It is deliberately simple —
one agent working the approved records in order; the agent-team fan-out comes
later.

Every fix ships through the discipline in
[references/fix-discipline.md](references/fix-discipline.md): control-test
(the failure must reproduce with the fix absent, or the fix is withdrawn
unbuilt) → author → verify (the signature gone, not lessened) → re-run the
original failure verbatim.

All `retroloop` commands run from the app checkout as
`cd ~/Developer/retroloop-app && bun run --silent retroloop <args>` (or plain
`retroloop <args>` if the binary is on PATH).

## 1 · Arm the finish watch

You need the retro id — the number the review session announced. If it was
not passed as the argument, ask the user for it.

Arm exactly one wait and let its EXIT be the notification:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/watch-review.sh" <retroId>
```

(Fallback, anywhere the script can't run:
`retroloop review wait --follow --retro <retroId> --timeout 600 --json`.)

**Never stand the watch down.** Exit 0 = the human pressed Finish, event JSON
on stdout. Exit 7 = timeout, nothing happened — re-arm immediately. A killed
watcher is re-armed immediately, never abandoned; the wait reads from the
store, so a press that lands while nothing is armed is still delivered to the
next watch. The watch ends at review close or on the human's explicit word,
and on nothing else.

## 2 · Close and export

When the finish arrives:

```
retroloop review close --retro <retroId> --json
retroloop export --retro <retroId> --out ~/.ai-team/retro/exports/retro-<n>.json --json
```

`review close` refuses unless the human has finished with every record
decided — if it refuses, read the message: pending or revise-marked records
mean the review is still the human's, so go no further and tell the user.

## 3 · Implement each approved record

Read the export. For each approved record, the human selected a solution and
an involvement — both are binding:

- **The selected solution is the one to build** — not the one you'd prefer.
  Its change footprint names the files, primarily in the personalization
  plugin (`~/Developer/my-plugin` by default).
- **Involvement**:
  - `autonomous` — implement and commit directly to the plugin repo, one
    commit per record, message citing the record id.
  - `pull-request` — implement on a branch, open a PR (or, with no remote,
    a branch plus a clear handoff note), and do not merge it yourself.
  - `interactive` — stop and work it through with the user in-session.
  - anything else / `undecided` — ask, don't guess.

Understand before touching: read the record's problem, root cause, and the
words the human wrote. A fix that contradicts the record's agreed direction
is wrong even if it works.

## 4 · Deploy and mark resolved

After the autonomous commits (and any merged PRs):

```
claude plugin update my-plugin@my-plugin
retroloop record resolve <recordId> --ref <commit-sha> --json
```

The update makes the next session start on the newest version of the plugin;
`record resolve` writes the receipt so the retro's ledger knows the fix
shipped. Report to the user: what shipped, what waits on a PR, what was left
interactive — with commit SHAs.
