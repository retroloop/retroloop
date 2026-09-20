---
name: setup
description: Bootstrap Retroloop on this machine — install the Retroloop app, start the local review server, and create the user's personalization plugin from the template.
disable-model-invocation: true
argument-hint: "<optional preferences, e.g. install directory>"
---

# /retroloop:setup — the bootstrap

You are setting up Retroloop for this user. Setup installs software, so **every
install step asks for consent before running** — name the command, say what it
does, then run it only on the user's yes. Walk the steps in order; at the end,
report the checklist. If a step fails, tell the user exactly what failed and
what to do — never improvise an alternative install path.

Everything Retroloop keeps lives under one root, `~/.retroloop`: the app in
`apps/`, the user's plugins in `plugins/`, and later the database, the session
folders and the exports. One root means nothing has to record where anything
went. `RETROLOOP_HOME` moves the root for a user who wants it elsewhere; use it
verbatim wherever this file writes `~/.retroloop` if it is already set.

If the user passed preferences as arguments (a different install directory, a
different plugin name), honor them wherever this file names a default.

## 1 · Verify bun

```
bun --version
```

Any version output means bun is present. If the command is missing, stop and
tell the user:

> Retroloop's app runs under [Bun](https://bun.sh). Install it with
> `curl -fsSL https://bun.sh/install | bash` (macOS/Linux) or
> `powershell -c "irm bun.sh/install.ps1 | iex"` (Windows), open a fresh
> terminal, and run `/retroloop:setup` again.

Do not install bun yourself.

## 2 · Install the Retroloop app

The app goes in the root, at `~/.retroloop/apps/retroloop`:

```
git clone https://github.com/retroloop/retroloop-app ~/.retroloop/apps/retroloop
cd ~/.retroloop/apps/retroloop && bun install
```

If the directory already exists with a checkout inside, skip the clone and run
`cd ~/.retroloop/apps/retroloop && git pull && bun install` instead.

Verify the CLI answers:

```
cd ~/.retroloop/apps/retroloop && bun run --silent retroloop --version
```

A bare version string on stdout means the app is installed.

**If the user wants the app somewhere else**, clone it there and tell them the
one thing that keeps it findable: `RETROLOOP_APP` in their environment, set to
that directory, in their shell profile. That variable is the whole escape
hatch — nothing is written to disk to remember the choice, and without it the
SessionStart hook and the finish watch look only in `~/.retroloop/apps/retroloop`
and report "not set up".

## 3 · Start the review server and verify it

```
cd ~/.retroloop/apps/retroloop && bun run --silent retroloop up --json
```

`up` is idempotent — it starts the server or reports the one already running.
Read the JSON it prints: it carries the server URL. Never pass `--bind`
yourself: the server binds `127.0.0.1` unless the human asks for the network.
Reviewing from a tablet is the human's own choice, made in his terminal:
`retroloop down && retroloop up --bind <this machine's LAN IP>` (wildcards such
as `0.0.0.0` are refused). If the JSON carries a `lanUrl`, he made that choice;
`url` is then that network address too, because a server bound to one interface
answers only there — hand him `url`, and leave `lanUrl`, the link for his other
device, alone unless he asks.

Verify the page actually serves:

```
curl -s -o /dev/null -w '%{http_code}' <the url from the JSON>
```

`200` means the review UI is up. Anything else: report the code and the `up`
output to the user verbatim.

## 4 · Create the personalization plugin

The plugin is `my`, and it lives at `~/.retroloop/plugins/my`. The name matters
beyond the folder: its skills load as `/my:<skill>`, so short is worth keeping.

```
git clone https://github.com/retroloop/personalization-template ~/.retroloop/plugins/my
cd ~/.retroloop/plugins/my && rm -rf .git && git init -b main
git add -A && git commit -m "my personalization plugin — created by Retroloop setup"
```

From this moment the plugin is the user's: the template is copied once, never
tracked upstream. If the user chose a name other than `my`, set it in
`.claude-plugin/plugin.json` (`name`) before committing, and use it in place of
`my` everywhere below. If the template still ships its own
`.claude-plugin/marketplace.json`, delete it — the marketplace is the parent
folder now, and a second one inside the plugin is a stale copy waiting to
confuse someone.

**The marketplace is `~/.retroloop/plugins` itself**, one local marketplace for
every plugin the loop ever builds. Write it:

```
mkdir -p ~/.retroloop/plugins/.claude-plugin
cat > ~/.retroloop/plugins/.claude-plugin/marketplace.json <<'JSON'
{
  "name": "my-marketplace",
  "owner": { "name": "me" },
  "plugins": [
    {
      "name": "my",
      "source": "./my",
      "description": "My personalization plugin — evolved one retro at a time."
    }
  ]
}
JSON
```

**Offer a shortcut to it, once.** The plugin is the thing the loop changes on
the user's behalf, and a hidden folder is a poor place to go looking. Ask where
they would like to browse it from — a folder they actually open, e.g.
`~/Developer/my` — and link it there:

```
ln -s ~/.retroloop/plugins/my <the path they chose>
```

The link is for their eyes only; every command still names the real path. If
they would rather not have one, drop it and move on.

**Offer a remote, once, and never again.** A backup of the plugin is the user's
call. If they want one it should be a **private** repository, named whatever
they like — `my` keeps it obvious which plugin it backs — and they run the
command themselves:

```
gh repo create <their-user>/my --private --source ~/.retroloop/plugins/my --push
```

If they decline, that is the answer for good: nothing in Retroloop asks again,
and the resolve lane pushes only when a remote already exists.

## 5 · Two choices, recorded in your plugin

Two questions, asked through the question tool, and both answers land in one
file the rest of Retroloop reads back. Neither is a one-time chance: the file
is plain text, so the user can edit it by hand or run setup again.

**1 · Where do you track issues?**

- **This tool only** *(default)* — the retrospective is the record, and
  nothing leaves Retroloop.
- **Elsewhere (GitHub, Asana, anything)** — after every finished review the
  closing session runs the plugin's own `/my:file-issues` skill, which the
  user adapts to their tracker, so the approved records also land where they
  already work.

**2 · Which model runs the manager and the tech leads?**

Default **Fable** — the model of the standing manager session and of each
worker team's tech lead. Their subagents run on **Opus** unless the user says
otherwise.

Write both answers into `~/.retroloop/plugins/my/retroloop.md`. The template
ships that file with the defaults already in it: overwrite the values, and
keep the shape exactly as it is — plain lines, one per choice.

```
# Retroloop

Choices recorded by /retroloop:setup. Plain lines; edit them by hand or run setup again.

tracking: this tool only
model: fable
subagent model: opus
```

`tracking:` is `this tool only` or `elsewhere`; `model:` and `subagent model:`
take anything `claude --model` accepts. The scripts read `model:` and the
review skill reads `tracking:`, so the spelling of those lines matters more
than the prose around them. Commit the file in the plugin.

Then make the folder the resolve lane keeps its working notes in — one per
agent, flat, and nothing in it is ever cleaned up:

```
mkdir -p ~/.retroloop/agents
```

**The launch rule ships with the plugin — show it, and ask.** The template
carries `.claude/settings.json` inside the plugin with one `permissions.allow`
entry, `Bash(claude --bg:*)`: the manager runs from this folder, and that rule
is what lets it launch worker teams as background sessions. It applies only to
sessions whose working directory is the plugin, so nothing else on the machine
is widened by it; worker teams run from the repository the change lands in and
rely on auto mode there. Print the rule, say that much, and ask through the
question tool whether to keep it or remove it. On remove, delete the file and
commit; the manager then stops at its first launch and says so. Never write
that rule anywhere else, and never into a local settings file.

**Then have the plugin folder trusted, or the rule is ignored.** Claude Code
reads a project's `permissions.allow` only in a workspace the human has
trusted; an untrusted one logs `Ignoring 1 permissions.allow entry` and runs
on the classifier alone. Trust is granted once, by the human, in a terminal:

```
cd ~/.retroloop/plugins/my && claude
```

Accept the trust dialog, then leave the session. Say exactly that, and say it
is the one step of setup only the human can take; do not write the trust entry
into Claude Code's own configuration yourself.

**Only if the user took a remote above**, one more permission rule is worth
adding: the resolve lane pushes the plugin through the plugin's own push
script, and that script has to be allowed. Name the rule, ask for consent, and
add it to `~/.claude/settings.json` only on their yes — a `permissions.allow`
entry reading:

```
Bash(bash */scripts/plugin-push.sh */.retroloop/plugins/my)
```

Their own edit is just as good as yours. If they would rather do it
themselves, or refuse the edit, print that one line, say it goes in
`permissions.allow` in `~/.claude/settings.json`, and move on. With no remote
there is nothing to push and nothing to allow.

## 6 · Register the plugin with Claude Code

```
claude plugin marketplace add ~/.retroloop/plugins
claude plugin install my@my-marketplace -y --json
```

The marketplace is the folder; the plugin is the entry inside it. Read the JSON
back — it says whether the install landed. After fixes ship, deploys are
`claude plugin update my@my-marketplace --json -y`, and that is the manager's
job, not the user's.

## 7 · The checklist — report it, honestly

Walk these and report each with its evidence (the actual command output), then
tell the user to restart their Claude Code session so the new plugin loads:

- **CLI answers** — `retroloop --version` printed a version, from
  `~/.retroloop/apps/retroloop`.
- **Server up** — `retroloop up --json` reported a URL.
- **Review page loads** — the URL answered 200.
- **Plugin created** — `~/.retroloop/plugins/my` is a git repo with one commit.
- **Choices recorded** — `retroloop.md` in the plugin names the tracking
  choice and the model.
- **`agents/` exists** — `~/.retroloop/agents` is there for the resolve lane's
  notes.
- **Launch rule kept or removed** — `~/.retroloop/plugins/my/.claude/settings.json`
  is present with `Bash(claude --bg:*)`, or the user chose to remove it.
- **Plugin folder trusted** — the human opened Claude Code in
  `~/.retroloop/plugins/my` once and accepted the trust dialog (report it as
  told, not as verified: nothing here can check it).
- **Marketplace registered** — the `marketplace.json` under
  `~/.retroloop/plugins/.claude-plugin/` exists, and
  `claude plugin marketplace list` shows `my-marketplace`.
- **Personalization plugin installed** — `claude plugin list` (or the
  `/plugin` menu) shows `my`.

Name the paths in the report: the app, the plugin, and the shortcut if they
took one. Anything unchecked: say so plainly, with what failed. An honest
partial setup beats a claimed complete one.

And say once what happens after a review, because it is the half of Retroloop
they have not seen yet: **after every finished review the manager — a
background session you can watch in `claude agents` — applies the records you
approved and releases your plugin; you will be told the one reload line to
type in sessions that were already open.**
