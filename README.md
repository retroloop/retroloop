# Retroloop

**A Claude Code plugin that turns the frictions from your AI sessions into permanent fixes — in a personalization plugin that exists just for you.**

In each AI session, you focus on your goal. The AI keeps running notes on everything that gets in the way. One command turns those notes into a reviewable retrospective — every issue with its evidence, a root cause, and solutions at increasing levels of strength, each showing exactly what would change in your personalization plugin. You pick the solution you prefer and your own level of involvement; then the resolve lane applies what you approved — a background manager delegates each record to a worker team, releases your plugin, and you type one reload line in sessions that were already open. The next session starts on the newest version of your setup.

**Before you start.** **Claude Code** is the client this plugin runs inside, and you install it yourself: get it from https://claude.com/claude-code. Everything else, setup checks for and offers to install — and installs only on your yes: **git**, which clones the app and the template and keeps your own plugin's history; **[Bun](https://bun.sh)**, the runtime the app runs on; and `unzip` and `curl`, which Bun's installer needs and which a minimal Linux image does not ship. Setup asks first whether to look into how to install what is missing on this machine, proposes the commands before running any of them, and on a machine whose rules forbid the install it prints the list to hand your IT and stops.

**Supported systems.** Built and tested on macOS. Linux is expected to work but is untested. Windows is not supported yet. Tested against a current Claude Code release; older builds are untested.

## Install

```
/plugin marketplace add retroloop/plugins
/plugin install retroloop@retroloop
/retroloop:setup
```

Setup installs the review app locally and creates your personalization plugin from the [template](https://github.com/retroloop/personalization-template). From that moment the plugin is yours — local by default, connected to GitHub only if you want it to be.

## Skills

| Skill | Who invokes it | What it does |
|---|---|---|
| `/retroloop:setup` | you | Bootstraps everything: the app, the server, your personalization plugin — then walks a verification checklist. |
| `notes` | the AI, as friction happens | Keeps evidence-gated friction notes during the session — frustration in your own words, wasted turns, broken guidance. |
| `/retroloop:review` | you, when the session winds down | Turns the notes into a retrospective you review in the local UI: approve, decline, or send back every record. |
| `/retroloop:resolve` | you, any time | Makes sure the manager is running and reports one line. The review skill runs it for you after every filed retrospective. |

## Agents

| Agent | What it does |
|---|---|
| `manager` | The standing background session: reads the finished retrospectives, researches each approved record's history, delegates it to a team, releases your plugin. |
| `tech-lead` | Runs one worker team — one record, from the history deep dive to the merge commit and the report. |
| `worker` | A team's subagent: the deep dive across every retrospective, or the part of the approved solution it was handed. |
| `reviewer` | A team's subagent: walks the checklist and returns `pass`, or the first failing item with the evidence. |

**The version monitor** tells every session when your plugin has a newer version than the one it loaded, with the one reload line to type.

## The pieces

- **This plugin** — the machinery everyone installs; updates pulled, never edited.
- **[retroloop-app](https://github.com/retroloop/retroloop-app)** — the local app: CLI, server, and the review UI where you and the AI align.
- **[personalization-template](https://github.com/retroloop/personalization-template)** — copied once by setup; from then on it's yours, and it evolves one retro at a time.

## Status

**Early.** Expect rough edges; file them. The version you are running is whatever `/plugin install` reports — the manifest is the only place a version number lives.

## License

MIT
