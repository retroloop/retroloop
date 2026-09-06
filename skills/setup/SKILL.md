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

Default home: `~/Developer/retroloop-app` (ask if the user prefers another
path — their argument wins).

```
git clone https://github.com/retroloop/retroloop-app ~/Developer/retroloop-app
cd ~/Developer/retroloop-app && bun install
```

If the directory already exists with a checkout inside, skip the clone and run
`cd ~/Developer/retroloop-app && git pull && bun install` instead.

Verify the CLI answers:

```
cd ~/Developer/retroloop-app && bun run --silent retroloop --version
```

A bare version string on stdout means the app is installed.

Now record where it went:

```
mkdir -p "${RETROLOOP_HOME:-$HOME/.ai-team/retro}" && printf '%s\n' "<the install dir>" > "${RETROLOOP_HOME:-$HOME/.ai-team/retro}/app-path"
```

This one line is how the SessionStart hook and the finish watch find the app
when it is not at the default path — without it, a user who chose their own
install directory is told "Retroloop is installed but not set up" at every
session start. `RETROLOOP_APP` in the environment overrides the file.

## 3 · Start the review server and verify it

```
cd ~/Developer/retroloop-app && bun run --silent retroloop up --json
```

`up` is idempotent — it starts the server or reports the one already running.
Read the JSON it prints: it carries the server URL. Never pass `--bind`
yourself: the server binds `127.0.0.1` unless the human asks for the network.
Reviewing from a tablet is the human's own choice, made in his terminal:
`retroloop down && retroloop up --bind <this machine's LAN IP>` (wildcards such
as `0.0.0.0` are refused). If the JSON carries a `lanUrl`, he made that choice;
hand him `url` and leave `lanUrl` alone unless he asks.

Verify the page actually serves:

```
curl -s -o /dev/null -w '%{http_code}' <the url from the JSON>
```

`200` means the review UI is up. Anything else: report the code and the `up`
output to the user verbatim.

## 4 · Create the personalization plugin

Default home: `~/Developer/my-plugin`; default name: `my-plugin` (the user may
choose another — use it consistently in every command below).

```
git clone https://github.com/retroloop/personalization-template ~/Developer/my-plugin
cd ~/Developer/my-plugin && rm -rf .git && git init -b main
git add -A && git commit -m "my personalization plugin — created by Retroloop setup"
```

From this moment the plugin is the user's: the template is copied once, never
tracked upstream. If the user chose a name other than `my-plugin`, set it in
`.claude-plugin/plugin.json` (`name`) and `.claude-plugin/marketplace.json`
(`name` and the plugin entry's `name`) before committing.

**Optional remote** (offer, don't push): if the user wants the plugin backed up
on GitHub it should be a **private** repository, and they run the command
themselves:

```
gh repo create <their-user>/my-plugin --private --source ~/Developer/my-plugin --push
```

## 5 · Register the plugin with Claude Code

```
claude plugin marketplace add ~/Developer/my-plugin
claude plugin install my-plugin@my-plugin
```

(The template ships its own single-plugin marketplace file, so the plugin's
directory is also its marketplace; after fixes ship, deploys are
`claude plugin update my-plugin@my-plugin`.)

## 6 · The checklist — report it, honestly

Walk these and report each with its evidence (the actual command output), then
tell the user to restart their Claude Code session so the new plugin loads:

- **CLI answers** — `retroloop --version` printed a version.
- **App path recorded** — `cat ~/.ai-team/retro/app-path` prints the install
  directory.
- **Server up** — `retroloop up --json` reported a URL.
- **Review page loads** — the URL answered 200.
- **Personalization plugin installed** — `claude plugin list` (or the
  `/plugin` menu) shows it.

Anything unchecked: say so plainly, with what failed. An honest partial setup
beats a claimed complete one.
