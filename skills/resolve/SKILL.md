---
name: resolve
description: Make sure the Retroloop manager is running — the standing background session that applies the records you approved. Reports one line.
disable-model-invocation: true
---

# /retroloop:resolve — make sure the manager is running

Run this, and report what it prints to the human **verbatim**, as one line:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/ensure-manager.sh"
```

That is the whole skill. The script takes no arguments, prints exactly one
line, and is safe to run any number of times — it starts the manager, resumes
it, or tells you it was already running. Nothing else belongs here: no
protocol, no waiting on anything, and no fixing. The work happens in the
manager's own session, not in yours.

The two lines it can print:

- **`running <sessionId>`** — the manager is up. Say so and stop.
- **`setup has not run; no manager`** — there is no personalization plugin yet.
  Tell the human to run `/retroloop:setup` first.

What the manager then does is its own business and is visible where background
sessions are: `claude agents`. It reads the finished retrospectives from the
app, delegates each approved record to a worker team, releases the plugin, and
the version monitor tells any open session the one reload line. You do none of
that here.
