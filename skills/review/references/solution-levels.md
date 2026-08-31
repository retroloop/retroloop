# Solution levels — the approval envelope

Every issue proposes solutions at **levels**. A level is not a size estimate —
it is the **approval envelope the human grants**: how much change to their
setup they authorize in one word. The human selects exactly one solution, and
the fixer may build *that solution at that level* and nothing bigger.

## What calibrates a level

**Uncertainty, side effects, and reversibility — never effort.** A ten-minute
change that alters what every future session sees is a bigger ask than an
hour-long change that touches one file nothing else reads. When choosing what
level to propose, ask:

- How sure are we this fixes the root? (uncertainty)
- What else could notice the change? (side effects)
- If it's wrong, what does undoing it cost? (reversibility)

Effort never enters the calibration. Proposing a higher level because the
lower one is "more work to write well" inverts the whole idea.

## The three levels

### L1 — words only: guidance text; nothing executes it, nothing conforms to it

Instruction lines, a sentence in an existing doc. Cheap, instant, fully
reversible — and it is *guidance in a crowded context*, which means it can be
missed. L1 is the right first envelope for most single-occurrence issues.

**Worked example** (the robotic-email issue): add 2–3 one-liners to the
instructions — *avoid robotic phrasing, keep it short, write like I talk.*

```
my-plugin/
└── instructions/
    └── global.md          [UPDATE]  2-3 style one-liners
```

### L2 — tune existing: behavior change inside artifacts that already exist

A dedicated skill, a changed rule in an existing hook, a reworded checklist —
the artifact class already exists in the plugin; the fix changes what it says
or adds one of its kind. Loads in context when relevant; still nothing
enforces it.

**Worked example**: a draft-email skill — the preferred writing style captured
as real guidelines: tone, length, sign-off, banned phrases — loaded whenever
emails are drafted.

```
my-plugin/
└── skills/
    └── draft-email/
        └── SKILL.md       [CREATE]  the preferred writing style
```

### L3 — add surface: something new that everything existing can safely ignore

A new enforcement point: a hook, a monitor, a script, a binary. Deterministic
where L1 and L2 are advisory — and the envelope is bigger because new surface
runs on every matching event, can misfire, and must be safe for everything
that already exists to ignore.

**Worked example**: the skill *plus enforcement* — a hook that runs on every
draft-email tool call and fails it unless the AI has read the draft-email
skill first. The style stops being optional; a robotic draft cannot slip
through, because the skill cannot be skipped.

```
my-plugin/
├── skills/
│   └── draft-email/
│       └── SKILL.md       [CREATE]  the style, as the drafting guideline
└── hooks/
    └── hooks.json         [UPDATE]  on each draft-email call: fail unless
                                     the skill was read
```

## Proposing well

- **Propose 1–3 solutions, each at the level it honestly needs** — often the
  same fix at two strengths (the L1 words, the L2 skill), letting the human
  buy exactly as much enforcement as the friction has earned.
- **Recommend one.** Mark the recommendation; a first occurrence usually
  recommends L1 or L2, and recurrence is what argues the escalation.
- **Every solution shows its change footprint** — the file tree of exactly
  what would be created or updated, so the envelope is visible before it is
  granted.
- **The selected level is a ceiling.** Building an unrequested hook under an
  approved L1 is a violation of the envelope even if the hook is good.
