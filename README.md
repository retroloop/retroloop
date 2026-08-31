# Retroloop

**A Claude Code plugin that turns the frictions from your AI sessions into permanent fixes — in a personalization plugin that exists just for you.**

In each AI session, you focus on your goal. The AI keeps running notes on everything that gets in the way. One command turns those notes into a reviewable retrospective — every issue with its evidence, a root cause, and solutions at increasing levels of strength, each showing exactly what would change in your personalization plugin. You pick the solution you prefer and your own level of involvement; the fixer implements what you approved and deploys it. The next session starts on the newest version of your setup.

## Install

```
/plugin marketplace add retroloop/plugins
/plugin install retroloop
/retroloop:setup
```

Setup installs the review app locally and creates your personalization plugin from the [template](https://github.com/retroloop/personalization-template). From that moment the plugin is yours — local by default, connected to GitHub only if you want it to be.

## Skills

| Skill | Who invokes it | What it does |
|---|---|---|
| `/retroloop:setup` | you | Bootstraps everything: the app, the server, your personalization plugin — then walks a verification checklist. |
| `notes` | the AI, as friction happens | Keeps evidence-gated friction notes during the session — frustration in your own words, wasted turns, broken guidance. |
| `/retroloop:review` | you, when the session winds down | Turns the notes into a retrospective you review in the local UI: approve, decline, or send back every record. |
| `/retroloop:fixer` | you, in a second terminal | Waits for your Finish, then implements the approved fixes in your personalization plugin and deploys them. |

## The pieces

- **This plugin** — the machinery everyone installs; updates pulled, never edited.
- **[retroloop-app](https://github.com/retroloop/retroloop-app)** — the local app: CLI, server, and the review UI where you and the AI align.
- **[personalization-template](https://github.com/retroloop/personalization-template)** — copied once by setup; from then on it's yours, and it evolves one retro at a time.

## Status

**Launching — v0.1.** Expect rough edges; file them. (Retroloop's own rough edges are exactly the kind of thing it exists to capture.)

## License

MIT
