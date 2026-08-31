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

## Where it goes

The chain fills the record's root-cause section: the incident line, each why
as question-and-answer, and the root on its own line. The proposed solutions
must answer the *root* — a solution that treats "why 1" while the root sits
lower is the pattern this method exists to catch.
