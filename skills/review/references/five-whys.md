# The five-whys root cause — from felt friction to a fixable cause

Every issue record carries a visible root-cause chain. Its job is to walk from
what the human *felt* to a cause the setup can actually *change* — because a
fix aimed at a symptom ships, feels done, and the friction comes back.

## The method

Start from the incident as it was felt, and ask "why?" of each answer:

```
incident   All email drafts written by the AI were too robotic.
why 1      Why do the drafts sound robotic? The AI falls back to its
           generic professional tone.
why 2      Why the generic tone? It knows nothing about how this human
           actually writes.
why 3      Why does it know nothing? The preferred style was never written
           down anywhere the AI reads.
root       There doesn't exist a skill that teaches the AI the human's
           preferred writing style.
```

Stop when the answer lands **inside the setup's reach** — an instruction, a
skill, a hook, a monitor, a binary: something a fix can create or change. That
is what qualifies an answer as a root:

- *"There doesn't exist a skill that teaches X"* — a model root. The fix is
  obvious from the root alone.
- *"The rule exists but only as guidance, and guidance got missed under
  load"* — a root; it points at enforcement.
- *"Two instructions contradict each other"* — a root; it points at the pair.

## The rules

**Three whys often suffice; five is a ceiling, not a quota.** The chain ends
when it reaches something fixable, not when it reaches five. Padding a chain
to five turns real reasoning into ceremony.

**"I forgot" is not a root cause.** Neither is "the AI made a mistake",
"wasn't careful enough", or any answer that blames attention. Ask why
forgetting was *possible*: what wasn't written down, wasn't loaded, wasn't
enforced? An attention-blaming root produces a try-harder fix, and try-harder
fixes don't survive the next session.

**The chain must be visible in the record.** The human reviews the reasoning,
not just the conclusion — a wrong "why 2" caught in review saves a fix aimed
at the wrong layer. Write the chain as it actually ran, one line per why.

**Stay evidence-side.** Each answer must be something this session's evidence
supports, not a theory about sessions you didn't see. If the chain needs a
fact you don't have, the record says so instead of inventing it.

## The drafter's rules

These five hold for whoever writes the record — the main agent, or a fork
drafting one group of frictions.

**The guidance you ran under is evidence.** The skills that were loaded, every
`CLAUDE.md` in scope, what a hook printed at you, the persona you were running
as: all of it is part of the session, and any of it can be the cause. An agent
that treats its own instructions as background rather than as evidence will
never find the root of a friction the instructions produced — and those are the
frictions this loop exists to catch.

**A root cause that lies in guidance cites it.** Name the file, name the plugin
version — it is visible in the skill's own base directory path — name the line,
and **quote it**. "The skill was unclear" is not a finding anybody can act on;
`skills/review/SKILL.md` at plugin 0.2.2, line 1056, saying *"this harness
re-invokes an agent when a background task EXITS and never when it prints a
line"*, is a finding with the fix already attached. A citation with no quote is
half of one: lines move, and then nothing records what the line used to say.

**Quote the human verbatim, garbles included.** He dictates, so words arrive
broken — and the broken words are the record of what he actually said. The
`verbatim` half carries them exactly; **the cleaned twin fixes dictation only**,
which means restored words and punctuation and nothing else. A cleaned quote
that tightens his point, drops his aside, or makes him sound more measured is a
paraphrase wearing a quote's clothes.

**Candidate earlier records take up to three word choices, and no
investigation.** Run one read query per friction —
`retroloop record list --all --text "<a distinctive word of the class>" --json`
— and when the first word returns nothing, try again: **single distinctive
words** of the class first, one per query, then a **two-word phrase**, and stop
at three. **Never generic words** — lead, test, review, agent and their like
match nearly every record, and matching everything is the same as matching
nothing. **List at most the ten most plausible by title**, **say which query
found them**, and put every query and its row count in the diagnostic data
beside them. Then leave them there: they are candidates for the resolving
side's history deep dive, and a drafter that opens them is doing the deep dive
it was told not to do.

**Every solution's first bullet says "(derived from this session only)".** One
session is one data point. It is not a disclaimer to be waived when a finding
feels general: it is what stops one friction from being written up as a
standing pattern, and it is what tells the human how much evidence he is
actually deciding on. A friction that really is recurring proves it through the
resolving side's history deep dive, not through the drafter's confidence.

## Where it goes

The chain fills the record's root-cause section: the incident line, each why
as question-and-answer, and the root on its own line. The proposed solutions
must answer the *root* — a solution that treats "why 1" while the root sits
lower is the pattern this method exists to catch.
