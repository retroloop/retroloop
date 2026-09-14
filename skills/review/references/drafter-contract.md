# The drafter contract — what each fork is handed

One fork drafts one group of frictions. It is handed two things and nothing
else: **the brief**, which says which frictions it has and where the evidence
for them is, and **the contract**, which says what a drafter does and does not
do. Both are below, to be sent as written.

The division is the point. The brief carries **pointers and the notes' own
suspect line, and no root cause of the main agent's own** — so the fork
re-derives the cause from evidence instead of confirming an opinion it was
handed. A brief that says "this is because the skill was missing a rule" gets
back a record that says the skill was missing a rule, and nobody checked.

## The brief

One per group, written by the main agent from the notes. Fill every angle
bracket; a placeholder left unfilled is a fork drafting from nothing.

```
Group: <the shared suspected cause or surface in one line, or "single">
Frictions:
  1. <what happened, one line> — notes entry <its time heading>; the session was <doing what>;
     commands or files involved: <paths, commands>; the notes' suspect: <skill, rule or gap, or
     "none named">
  2. …
Your words in the notes, verbatim: <the "their words" lines of those entries, copied exactly>
Compaction: this session compacted <N> times before drafting; snapshots: <list or none>
Write the draft to: ~/.retroloop/sessions/<id>/agents/draft-<group>/records.json
Report one line when done.
```

**The human's words are copied, never summarized.** The `their words` lines of
a notes entry are the one part of the evidence a fork must not re-derive: they
are what he actually said, and a brief that paraphrases them hands the drafter
a paraphrase to quote back to him.

## The fork contract

Sent as the head of the fork's prompt, with the brief after it.

```
You are a fork of the main agent, drafting the records of one group of frictions from this
session. You hold the whole session in your context; that is your evidence. Draft each friction
as one record in the revision-file shape the review skill defines, and nothing else.

- Five whys from evidence. Every why points at something in this session that answers it: a
  message, a command and its output, a file, a rule you were running under. Stop when the chain
  bottoms out.
- The guidance you ran under is evidence. If the cause is a skill, a CLAUDE.md line, a hook's
  output, a persona, or missing guidance, name the file, the plugin version from the skill's base
  directory path, and the line, and quote it.
- Quote the human verbatim from your context, garbles included; the cleaned twin fixes dictation
  only.
- One to three solutions, lowest level first, exactly one recommended, each footprint a tagged
  file tree whose update targets you verified exist. Every solution's first bullet says
  "(derived from this session only)".
- Candidate earlier records: run one read query per friction —
  retroloop record list --all --text "<two or three words of the class>" --json — and list what
  it returns under the diagnostic data heading "candidate earlier records (by text search, not
  verified)". They live there and nowhere else. Do not investigate them and do not claim a
  recurrence.
- Diagnostic data: fill every heading of the skeleton, "none" where empty. Everything the
  resolver would otherwise have to rediscover: tools, arguments, outputs, errors, paths, versions,
  what was tried, the quotes you relied on. Say where evidence predates a compaction.
- Where you disagree with the notes' suspect line, say so in the root cause.
- Write the draft file and report one line: the path and the record count. Do not file a
  revision, do not run any command that writes, do not touch the notes or the wiki, do not spawn
  agents, do not message anyone.
```

## What the fork writes

`~/.retroloop/sessions/<id>/agents/draft-<group>/records.json` — a JSON array of
record objects in the revision file's record shape, and nothing around it:

```json
[ { "rid": "r-…", "num": 0, "title": "…", "…": "…" }, … ]
```

**`rid` and `num` are the main agent's to mint, not the fork's.** A fork
drafting in parallel with two others cannot know which numbers are free, and
two forks that both mint `1` cost a round. A fork writes a working slug it
thinks fits and leaves `num` at `0`; the main agent settles both when it
assembles, and the density rule in the skill's "Identity" section is what
settles them.

## The rules that produced this shape

**A fork, not a fresh agent.** A fresh agent starts with nothing and there is
no tool that lets it read this session's transcript, so the evidence a root
cause needs — what was actually run, what came back, what the agent was reading
at the time — cannot reach it. A fork is a copy of the main agent on the same
model, holding the whole conversation. That is the only reason the drafting is
delegated at all.

**In parallel, and all at once.** Every fork is launched in the same message,
so they run at the same time rather than one after another. The main agent then
waits for every completion notification before it assembles anything.

**One report line, back to the main agent.** A fork does not file, does not
comment, and does not talk to the human. Everything it found is in its draft
file, and the one line it reports says where that file is and how many records
are in it.
