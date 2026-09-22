---
name: setup
description: Bootstrap Retroloop on this machine — install the Retroloop app, start the local review server, and create the user's personalization plugin from the template.
disable-model-invocation: true
argument-hint: "<optional preferences, e.g. install directory>"
---

# /retroloop:setup — the bootstrap

You are setting up Retroloop for this user. Setup installs software, so **every
install step asks for consent before running** — name the command, say what it
does, ask through the question panel, then run it only on the user's yes. Walk
the steps in order; at the end, report the checklist. If a step fails, tell the
user exactly what failed and what to do. Step 1 is the one step that works out
a route for this machine and proposes it before anything runs; everywhere else,
run the commands as they are written here and never invent an install path of
your own.

Everything Retroloop keeps lives under one root, `~/.retroloop`: the app in
`apps/`, the user's plugins in `plugins/`, and later the database, the session
folders and the exports. One root means nothing has to record where anything
went. `RETROLOOP_HOME` moves the root for a user who wants it elsewhere; use it
verbatim wherever this file writes `~/.retroloop` if it is already set.

If the user passed preferences as arguments (a different install directory, a
different plugin name), honor them wherever this file names a default.

**Every question goes through the question panel.** Ask with the
`AskUserQuestion` tool, never as prose in a message: the user sees the options
laid out and picks one, and the panel adds a free-text choice of its own, so
never write one into the options yourself: a question whose other answer is a
value the user types lists just the real choices, and lets the panel carry the
rest.

The panel's own shape is not yours to choose, and a question that breaks it
never draws at all:

- **Two to four written options**, each one a real choice. One option is not a
  panel, so a question with a single obvious answer still needs a second that
  genuinely differs — never "type your own", which is the free-text choice the
  panel already adds by itself.
- **A header of at most twelve characters** — the chip the panel shows above
  the question. Each question below names its own.
- **A label of one to five words** on every option, `(Recommended)` aside.
  Keep the label short and put the reasoning underneath, in the description
  line: one line, plain words, what happens if this one is chosen.

Every question carries a recommendation — the option you recommend comes
first, and its label ends with `(Recommended)`. When you are genuinely unsure
which option is right for this user, say so in the question itself and mark
nothing; a recommendation you do not believe is worse than none. Each question
below is written the way the panel shows it: the header, the question
sentence, then its options, one line of description each.

## 1 · Check what this machine already has

Setup needs four tools. Three of them its own commands run: **bun**, the
runtime the Retroloop app runs on; **git**, which clones the app and the
template and keeps the user's plugin history; and **curl**, which step 3 asks
the review page with. The fourth, **unzip**, together with curl again, is what
Bun's own installer needs — it downloads with curl and unpacks with unzip — so
unzip only matters if Bun has to be installed. All four are checked up front so
the answer to "what is missing" is complete in one pass, before a route is
worked out. Check all four before touching anything:

```
bun --version
git --version
unzip -v
curl --version
```

Any version output means the tool is present. This step only looks — nothing on
this machine changes before the user says so, which is what makes setup safe to
run again from here.

If all four answer, say so and go on to step 2:

> Everything is already present. Nothing to install.

If something is missing, say what is missing and what each missing one is for.
Name the tools this machine actually lacks — the question below is a shape, not
a sentence to copy — and ask it through the question panel, and nothing more:

> **<the missing tools, named> are missing. Shall I look into how to install them on this machine?**
>
> Header: `Install`
>
> - **Look into it (Recommended)** — work out the way that fits this machine and show you the commands before anything runs.
> - **Not now** — stop here and print the list of what is missing, for you to install yourself.

With only Bun missing that reads `Bun is missing. Shall I look into how to
install it on this machine?`; the two option lines never change. Do not propose
a command yet, and do not install anything yet.

### On a yes, understand the machine before proposing anything

Only after that yes, work out where you are. There is no single right way to
install these tools: the right way is a property of this machine, not of a
recipe, and the same command line that is correct on a rented Linux box is
wrong or forbidden on a work laptop. Establish, with short read-only commands:

- **The operating system, and the package manager that is actually present** —
  `apt-get`, `dnf`, `apk` and `brew` are the likely ones. Check; never assume.
- **Whether elevation is usable at all** — start with what is passive: `id -u`,
  the groups the user is in, whether the package manager's own directories are
  writable. Leave `sudo -n true` until last, and only if those leave the answer
  open: sudo's defaults mean an attempt by a user who is not permitted is
  logged and mailed to the administrator, so on the managed machine this whole
  section is written for, the probe is not a free look. Never run a command
  that can block on a password prompt.
- **Signs of a corporate or managed machine** — no administrator rights, a
  company proxy or an internal package mirror in the environment or in the
  package manager's configuration, device-management software.
- **Anything already loaded in this session that says how software is installed
  here** — a skill, a `CLAUDE.md` or another project instruction file, standing
  session context. These win over anything you would otherwise choose, so read
  them before you decide, and say which one you are following:

> This looks like a managed machine, and your instructions say installs go through the internal mirror. I'll follow that.

### Then propose one route, and ask how they want to approve it

Out of that look comes **one** proposal — the route that fits this machine, not
a menu of options for the user to weigh. Write the exact commands in the order
they run, one plain line each saying what that command does, and one sentence
saying why this route on this machine. Then ask, through the question panel,
once, for the whole missing set — never one question per tool:

> **Approve all at once, or one at a time?**
>
> Header: `Approval`
>
> - **All at once (Recommended)** — run the commands above in order; you have seen every one of them.
> - **One at a time** — stop for a yes before each command.

On **approve all at once**, run them in order, then re-check the four tools and
report what is now present. On **one at a time**, stop for a yes before each
command. Either way nothing runs that was not shown first. Anything you cannot
run goes in the same message, marked plainly as theirs to do — on macOS the git
installer opens a window a person has to click through, so git there is always
a hand-off.

### When the machine's rules block the install, stop cleanly

If the look finds no usable way — no administrator rights and no usable `sudo`,
a mirror that refuses, a policy that says ask IT — do not improvise around it
and do not try anyway. Print what to ask IT for: the tools by name, why each is
needed, and the command an administrator would run. Then stop:

> Your machine's rules block this. Ask IT for: unzip, curl, Bun. Then re-run setup.

That same block is what you print on a plain "no". The stop is clean because
nothing was half-installed — setup is a checklist, so running it again picks up
from what is actually on the machine rather than from anything remembered.

### If you installed Bun in this run, call it by the path that install produced

Installing Bun mid-run does not make the word `bun` work mid-run when Bun's own
installer did it: that installer appends a line to a shell start-up file, and
the shells the rest of this run uses never read it. A package manager usually
does put Bun straight on the path, so which case you are in depends on the
route you took.

So after the install, ask the bare word first — `bun --version`. If it answers,
nothing needs substituting and the rest of this file is fine as written. If it
does not, call Bun for the remainder of setup by the full path the install
actually produced, and get that path from whatever did the installing — the
installer's own closing lines, the package manager's file list, or `brew
--prefix bun` with `/bin/bun` on the end. For Bun's own installer that path is
`${BUN_INSTALL:-$HOME/.bun}/bin/bun`. Use whichever path you established
everywhere below this file writes `bun`.

Once Bun answers, check that a script shell finds it too — `bash -c 'command -v
bun'`, which is non-interactive and reads no start-up file, but inherits this
session's environment. Retroloop's hooks and watch scripts run in exactly that
kind of shell, so that is the case worth testing; a lookup under a wiped
environment proves nothing, because nothing Retroloop runs works that way. If
it prints a path, there is nothing to fix. If it prints nothing, fix it in the
way that fits this machine, the same way you chose the install route — and
that fix goes through the same consent as an install, because it is one more
change to someone's machine. Name the exact file and the exact line, then ask
through the question panel:

> **Script shells cannot find Bun. Shall I fix that?**
>
> Header: `Bun on path`
>
> - **Make the change (Recommended)** — the one line named above, in the file named above, and nothing else.
> - **Leave it to me** — the line is printed for you instead; until it is there, Retroloop's hooks and watch scripts cannot find Bun.

## 2 · Install the Retroloop app

The app goes in the root, at `~/.retroloop/apps/retroloop`:

```
git clone https://github.com/retroloop/retroloop-app ~/.retroloop/apps/retroloop
cd ~/.retroloop/apps/retroloop && bun install
```

If the directory already exists with a checkout inside, skip the clone and run
`cd ~/.retroloop/apps/retroloop && git pull && bun install` instead.

Installing the dependencies does not build the review page, and the server
answers `503` until it exists — so build it now, right here, either way:

```
cd ~/.retroloop/apps/retroloop && bun run --filter '@retro/web' build
```

It takes a second or two. Without it the link step 3 hands over opens nothing.

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
Read the JSON it prints: it carries the server URL, and that URL always names
the machine you are on. **The review server only ever listens on this machine.**
There is no network address to offer and nothing to type that changes it — the
page has no password, so being reachable from anywhere else would mean anyone
who found it could read the human's own words and write decisions on them.

**Reaching the page from another computer — forward the port over SSH.** When
Retroloop runs on a machine the human reaches over SSH, the way in is their own
secure login. They run this on their **own computer**, not on the server, with
the port the JSON reported (`24100` is the default) and their own login in place
of `you@your-server`:

```
ssh -N -L 24100:127.0.0.1:24100 you@your-server
```

Then they open `http://localhost:24100`. The command holds the connection open
and prints nothing; it is stopped with Ctrl-C when they are done.

**If they already run Retroloop on their own computer**, that local port is
taken, so forward to a free one instead — the first number is theirs to choose,
the second pair is the server's:

```
ssh -N -L 24101:127.0.0.1:24100 you@your-server
```

Then they open `http://localhost:24101`. Either form works, because the review
page asks its own server for data at a relative address and so does not care
which local port it is opened on.

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
```

Check the identity git would use: `cd ~/.retroloop/plugins/my && git config
user.name; git config user.email`. If either prints nothing, git invents one
from the account and the machine name. Ask which name and email the plugin's
own history should carry, through the question panel, and recommend whatever
git already reports — it is the identity the user's other repositories carry:

> **Which name and email should your plugin's history carry?**
>
> Header: `Git identity`
>
> - **Use this identity (Recommended)** — `<the name git reports>`, `<the email git reports>`: the identity your other repositories already use, written into this repository so it holds whatever your global one becomes later.
> - **Follow your global identity** — nothing is written here, and every commit takes whatever `git config --global` says at the time.

Both are real answers. Any other name and email is typed into the panel's own
free-text choice.

If git reports neither, there is nothing to recommend, and the question says so
itself rather than dressing a guess up as advice. Ask this instead, through the
same question panel:

> **This machine has no git identity set, so I have nothing to recommend here. Which name and email should your plugin's history carry?**
>
> Header: `Git identity`
>
> - **Let git invent one** — git builds a name and email from your account and this machine's name, and the plugin's history carries that.
> - **Use a neutral identity** — the history carries `me <me@localhost>` instead, so your account and this machine's name stay out of it.

Then write the answer into this repository, and nowhere else — the identity git
reports, the neutral one, or whatever came back from the free-text choice:

```
cd ~/.retroloop/plugins/my && git config user.name "<name>" && git config user.email "<email>"
```

On **Follow your global identity** or **Let git invent one** there is nothing
to write: git works an author out for itself on every commit, and the plugin's
history follows it.

Then make the first commit:

```
cd ~/.retroloop/plugins/my && git add -A && git commit -m "my personalization plugin — created by Retroloop setup"
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
the user's behalf, and a hidden folder is a poor place to go looking. Ask through
the question panel:

> **Where would you like to browse your plugin from?**
>
> Header: `Shortcut`
>
> - **`~/Developer/my` (Recommended)** — a folder you already open, one link away from the real thing.
> - **No shortcut** — nothing is linked; the plugin stays at `~/.retroloop/plugins/my`.

Any other folder is typed into the panel's own free-text choice. Then link it
there:

```
ln -s ~/.retroloop/plugins/my <the path they chose>
```

The link is for their eyes only; every command still names the real path. If
they would rather not have one, drop it and move on.

## 5 · Two choices, recorded in your plugin

Two questions, and both answers land in one file the rest of Retroloop reads
back. Neither is a one-time chance: the file is plain text, so the user can
edit it by hand or run setup again.

**1 · Issue tracking.** Ask through the question panel:

> **Where do you track issues?**
>
> Header: `Tracking`
>
> - **This tool only (Recommended)** — the retrospective is the record, and nothing leaves Retroloop.
> - **Elsewhere** — GitHub, Asana, anything: after every finished review the closing session runs your plugin's own `/my:file-issues` skill, which you adapt to your tracker, so the approved records land where you already work.

**2 · The model.** Ask through the question panel:

> **Which model runs the manager and the tech leads?**
>
> Header: `Model`
>
> - **Fable (Recommended)** — the model of the standing manager session and of each worker team's tech lead.
> - **Opus** — the heavier model on the manager and the leads as well.

Their subagents run on **Opus** either way, unless the user says otherwise. Any
other model is typed into the panel's own free-text choice.

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
question panel whether to keep it or remove it:

> **Keep the launch rule that lets the manager start worker teams?**
>
> Header: `Launch rule`
>
> - **Keep it (Recommended)** — the manager can launch worker teams; the rule reaches only sessions running from this folder.
> - **Remove it** — the file is deleted and committed, and the manager stops at its first launch and says so.

Never write that rule anywhere else, and never into a local settings file.

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

First, verify the short command the way every later session calls it:

```
retroloop --version
```

The plugin ships that command, so it is on the search path of every session
Retroloop is installed in: nothing is installed for it, and there is no
directory to change into first. A version string means every later session
reaches Retroloop by that name alone. If it is not found here, say so plainly
and carry on — this session began before the plugin version that ships it, and
the restart at the end of this checklist is what brings it in.

Walk these and report each with its evidence (the actual command output), then
tell the user to restart their Claude Code session so the new plugin loads:

- **CLI answers** — `retroloop --version` printed a version, from
  `~/.retroloop/apps/retroloop`.
- **Short command works** — plain `retroloop --version` answered, with nothing
  to change into first; it is the form every later session uses. If it did not
  answer here, say it counts from the next session, which is the restart this
  checklist already asks for.
- **Server up** — `retroloop up --json` reported a URL.
- **Review page loads** — the URL answered 200.
- **Plugin created** — `~/.retroloop/plugins/my` is a git repo with one commit,
  authored by the name and email the user confirmed.
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
