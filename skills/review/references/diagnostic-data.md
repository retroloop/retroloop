# Diagnostic data — the evidence a record carries with it

Every record carries a `diagnosticData` field: a required, non-empty markdown
string holding everything the resolving side would otherwise have to
rediscover. It is written at drafting time, by the agent that was there, and it
is the only part of a record that survives the session it came from.

## Why it is there

The field exists to give the complete picture to the resolver side — the tools,
the arguments, everything related — so that it stays grounded on facts and does
not invent, while still doing its own deep dive from a strong start.

Both halves are load-bearing. A resolver with no evidence **invents**: it reads
a root cause, cannot check it, and builds against a story. A resolver handed a
conclusion and told to trust it does not deep-dive at all. Diagnostic data is
the third thing — the facts, unargued, so the deep dive starts from something
solid instead of from scratch.

It is not a second root cause and not a summary of the record. The narrative
fields say what happened and why; this one says **what was observed**, in
enough detail that someone who was not there can re-derive the same conclusion
or a different one.

## The skeleton

Nine headings, in this order, every one of them present. **A heading carries
the literal `none` when it is empty** — an omitted heading reads as forgotten,
and `none` reads as checked and empty.

```
- **commands and outputs** — every command run and what it printed, verbatim.
- **error text** — the exact message, unabridged, or `none`.
- **paths and line references** — `file:line` for everything the record names.
- **commits and versions** — the commits in play, and the versions of what was running.
- **environment** — model, permission mode, plugin versions.
- **what was tried** — each attempt, and how it failed.
- **quotes relied on** — the human's words this record rests on.
- **candidate earlier records (by text search, not verified)** — every
  `record list --all --text` query run and its row count, which query found them,
  and at most the ten most plausible by title.
- **limits of this evidence** — what is missing, what is inferred, what predates a compaction.
```

Three of them are easy to get wrong:

- **`environment` is the run, not the machine.** The model, the permission
  mode, and the versions of every plugin that was loaded. It is how a resolver
  tells "this broke under `acceptEdits`" from "this broke".
- **`candidate earlier records (by text search, not verified)` is a raw search
  result and says so in its own heading.** What the queries returned, not what
  they mean. Nothing here is investigated, no prior is confirmed, and a record
  that says "this recurred" has made a claim its author did not check. **The
  recurrence judgment belongs to the resolver's history deep dive**, which has
  the tools and the time for it. Record **every query and its row count**, not
  just the one that worked, and **say which query found them** — the search is a
  substring match over the title, slug, problem and root cause, so a hit on a
  distinctive word and a hit on a common one are worth completely different
  amounts, and only the counts tell them apart. Up to three word choices, at
  most ten records listed, by title.
- **`limits of this evidence` is where compaction lands.** Say which parts rest
  on the transcript and which rest on the notes because the transcript is gone.
  A resolver that knows an observation came from a notes entry rather than from
  a command's output weighs it correctly.

## Where it goes

One field on the record, `diagnosticData`, carrying the whole skeleton as
markdown. The same safe subset as every other prose field — bold, `code`,
bullets, blockquotes, fenced blocks — so headings are **bold-lead bullets**
rather than `#` headings, which do not render.

Long command output goes in a triple-backtick fenced block, whose contents are
never parsed. Do not abridge it to fit: an elided output is the line the
resolver needed.

## A worked example

The diagnostic data of the deploy-lock record in the review skill's own
whole-record example:

```
- **commands and outputs** — `./scripts/deploy.sh staging` printed
  `waiting for lock…` and then nothing for 40 minutes. `ls -l /var/run/deploy.lock`
  showed it written at 02:14. `ps -p 4411` — the PID from the 02:14 deploy's log —
  returned nothing.
- **error text** — none. The failure is silence: nothing is printed after
  `waiting for lock…`, and the wait has no deadline to end it.
- **paths and line references** — `scripts/deploy.sh:63` takes the lock;
  `lib/lock.ts:20-34` is `acquire()`, which writes an empty file; `lib/lock.ts:41`
  releases it, and runs only on a clean exit.
- **commits and versions** — `lib/lock.ts` unchanged since `a3f21c9` (2025-11-04);
  `scripts/deploy.sh` last changed in `7d0e114`. Node 22.3.0.
- **environment** — model: claude-opus-5; permission mode: acceptEdits;
  plugin versions: retroloop 0.2.2.
- **what was tried** — waited 40 minutes; re-ran the deploy and waited again;
  deleted the lock file by hand, after which the deploy finished in 90 seconds.
- **quotes relied on** — "this thing has been sitting there for ages doing nothing",
  said while watching the deploy log.
- **candidate earlier records (by text search, not verified)** — three queries:
  `--text "advisory"` returned 0 rows, `--text "lockfile"` returned 2, `--text "deploy lock"`
  returned 1 already among them. `lockfile` is the query that found these two:
  `r-slow-deploys` (retro 4, declined) and `r-lockfile-perms` (retro 9, resolved).
  Neither was opened.
- **limits of this evidence** — that the 02:14 holder was killed is inferred from the
  file's mtime and the missing PID; nobody saw it die. The first 20 minutes of the wait
  predate this session's one compaction and rest on the 09:12 notes entry rather than on
  the transcript.
```

Read it against that record's root cause: every why in the chain has something
here that answers it, and the one inference is marked as one.
