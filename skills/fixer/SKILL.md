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

Two paths, and everything below is one or the other:

- **the app** — `~/.retroloop/apps/retroloop`. Run `retroloop` commands as
  `cd ~/.retroloop/apps/retroloop && bun run --silent retroloop <args>`, or as
  plain `retroloop <args>` if the binary is on PATH. If neither works,
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/watch-review.sh" where` prints what the
  resolver actually found and what each source is worth.
- **the plugin** — `~/.retroloop/plugins/my`, the user's own personalization
  plugin and the place nearly every fix lands.

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
retroloop export --retro <retroId> --out ~/.retroloop/retros/<retroId>/retro.json --json
```

`review close` refuses unless the human has finished with every record
decided — if it refuses, read the message: pending or revise-marked records
mean the review is still the human's, so go no further and tell the user.

Every export lands under `~/.retroloop/retros/<retroId>/retro.json`, one folder
per retro. That is not filing for its own sake: the review skill's class check
searches those files for the prior instances of a recurring friction, and a
retro written anywhere else is one the next retro cannot learn from.

## 3 · Implement each approved record

Read the export. For each approved record, the human selected a solution and
an involvement — both are binding:

- **The selected solution is the one to build** — not the one you'd prefer.
  Its change footprint names the files, primarily in the personalization
  plugin (`~/.retroloop/plugins/my`).
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

## 4 · Release the plugin

A fix that is committed but not deployed has changed nothing: Claude Code runs
the **installed copy** of the plugin, and the version in `plugin.json` is the
only signal that tells it to take a new one. So the release is four commands in
one order, and none of them is a question for the human.

```
# 1 · bump the patch number in ~/.retroloop/plugins/my/.claude-plugin/plugin.json
#     (0.1.4 → 0.1.5). Silently: it is bookkeeping, not news.
cd ~/.retroloop/plugins/my && git add -A && git commit -m "<what shipped, citing the record ids>"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/plugin-push.sh" ~/.retroloop/plugins/my
claude plugin update my@my-marketplace --json -y
```

- **The bump is silent and it is not optional.** Without it `plugin update`
  has nothing to update to and the fix stays on disk, unloaded.
- **`plugin-push.sh` handles the remote question for you.** With a remote it
  pushes and says so in one line; without one it does nothing and says nothing.
  A remote is the user's opt-in, offered once at setup — never ask for one
  here.
- **Read the update's JSON and check `"outcome":"ok"`.** Anything else is a
  failed release: say what it said, and do not report the fix as shipped.

Then mark the records resolved, so the retro's ledger carries the receipt:

```
retroloop record resolve <recordId> --ref <commit-sha> --json
```

## 5 · Report

Tell the human what shipped, what waits on a PR, what was left interactive —
with commit SHAs. Then, about the release itself, exactly this one line and
nothing more about versions, caches or reloading:

> Plugin released as <version>. In any Claude Code session that is already open, type /reload-plugins once. New sessions need nothing.

It is one line because it holds the only two facts the human can act on: the
open session needs one command, and the next one needs nothing.
