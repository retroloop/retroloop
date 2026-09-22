#!/usr/bin/env bash
# shellcheck shell=bash
#
# The one place that decides which retroloop CLI to run. SOURCE this file —
# executing it does nothing.
#
#     . "${BASH_SOURCE[0]%/*}/resolve-cli.sh"
#     retroloop_resolve_cli && "${RETROLOOP_CLI[@]}" --version
#
# There used to be two resolvers: the SessionStart hook probed PATH and one
# hardcoded directory, the finish watch had its own. A user who installed the
# app anywhere else was told "Retroloop is installed but not set up" at every
# session start, forever. One resolver, one answer, every caller — the hook,
# the two watch scripts, and `bin/retroloop`, the command this plugin ships.
#
# That shipped command is the one caller this file must not answer with. It
# lives on every session's PATH, so step 1 below would hand it back to itself
# and it would run itself for ever; and the hook would greet a machine that
# never ran setup with "this session is tracked". Both are prevented by one
# marker, `bin/.retroloop-bin`, which sits beside the shipped command and which
# step 1 looks for before it accepts a hit.
#
# And step 1 walks PATH itself rather than asking the shell "which retroloop?".
# The shell answers with the FIRST one, which is almost always the shipped
# command, because Claude Code puts the plugin's bin directory near the front.
# Skipping that single answer would end the rung there and never see a user's
# own `retroloop` a couple of entries later — which is the answer that outranks
# everything. So the rung is every PATH entry, in order, and the first one
# holding a `retroloop` that is not the shipped command wins.
#
# Then there was a pointer file — a line on disk naming the install — to cover
# the user who chose their own directory. It is gone: Retroloop now has ONE
# root, `~/.retroloop`, and the app has one place inside it,
# `<root>/apps/retroloop`. A fixed place needs no record of where it is. The
# user who still wants the app elsewhere sets `RETROLOOP_APP`, which is a
# statement about this shell and needs no file to stay true.
#
# AND IT FINDS BUN ITSELF. Three of the four answers below are a .ts file that
# Bun runs, and this file used to hand back the bare word `bun` for that. The
# shells Retroloop actually uses — the hooks Claude Code fires, the two watch
# scripts — are not the shell a person types into: on Debian and Ubuntu the
# start-up file every account gets stops early for exactly those shells, above
# the line Bun's installer appends at the bottom. So a machine with a healthy
# Bun answers nothing to `bun`, and the failure arrives far from its cause, in
# a watch that dies with `bun: command not found` while setup reported success.
# The lookup below goes and reads the places Bun really is, and every answer
# carries Bun's full path. Nothing is written, installed or linked, no
# administrator rights are needed and nobody is asked anything.
#
# On success it fills:
#   RETROLOOP_CLI          the command as an array (command + args)
#   RETROLOOP_CLI_SOURCE   path · env · default · repo
#   RETROLOOP_BUN_PATH     the Bun that command runs, empty when it needs none
# and returns 0. On a miss RETROLOOP_CLI is empty, it returns 1, and
#   RETROLOOP_CLI_MISS     none · no-bun
# says which of the two things is missing — Retroloop, or Bun. The messages a
# human reads are chosen off that: "run setup" is the wrong advice for someone
# whose setup already succeeded and whose Bun is what is hiding.
#
# Resolution order, first hit wins:
#   1 path     the first `retroloop` along PATH that is not the command this
#              plugin ships
#   2 env      $RETROLOOP_APP, then $WATCH_REVIEW_CLI (the older spelling)
#   3 default  <root>/apps/retroloop/apps/cli/src/bin.ts, where <root> is
#              $RETROLOOP_HOME, else ~/.retroloop
#   4 repo     <repo root>/apps/cli/src/bin.ts, for a caller that passes one
#              (the finish watch does; the hook does not, so no `git` runs at
#              session start)
#
# Bun order, first runnable hit wins:
#   $RETROLOOP_BUN · `command -v bun` · $BUN_INSTALL/bin/bun · ~/.bun/bin/bun ·
#   then the fixed folders in RETROLOOP_BUN_DIRS_DEFAULT below
#
# RETROLOOP_BUN is the escape hatch, for a Bun in a place no list can know:
# set it to the bun program itself, not to a folder. It is a statement about
# this shell, like RETROLOOP_APP, so it beats every other rung — and one that
# names nothing runnable falls through rather than aborting a session start.
# RETROLOOP_BUN_DIRS replaces the fixed folder list wholesale; it is the seam
# the suite needs to prove the no-Bun-anywhere case on a machine that does have
# Bun in one of those folders, and it is not something a person should need.
#
# `RETRO_HOME` is retired and is read nowhere: a stale one in someone's profile
# must not be able to move the answer.
#
# It runs at EVERY session start, so it costs two file tests per PATH entry, a
# handful more for Bun, and at most one `command -v` each: no network, no
# `git`. It never RUNS the CLI or Bun — a candidate is tested for being
# runnable and nothing more — and it is safe under `set -u`, `set -e` and
# `set -o pipefail`.

RETROLOOP_CLI=()
RETROLOOP_CLI_SOURCE=''
RETROLOOP_CLI_MISS=''
RETROLOOP_BUN_PATH=''

# The fixed folders, walked last and in this order: Homebrew on an Apple Mac,
# the conventional place a person links a program into, Homebrew on Linux, and
# what a Linux package manager would use.
RETROLOOP_BUN_DIRS_DEFAULT='/opt/homebrew/bin:/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/usr/bin'

# Is this candidate a Bun we could actually run? It has to be an absolute path,
# because the answer is handed to other scripts that run in other directories;
# and it has to be a file we may execute, so a stale guess and a leftover
# folder are skipped rather than passed on. `command -v` answering with the
# name of a shell function rather than a path is refused by the same test.
retroloop_bun_ok() { # <candidate>
  local c="${1:-}"
  case "$c" in
    /*) ;;
    *) return 1 ;;
  esac
  [ -f "$c" ] && [ -x "$c" ] || return 1
  RETROLOOP_BUN_PATH="$c"
  return 0
}

# Where Bun is. Fills RETROLOOP_BUN_PATH and returns 0; on a total miss it
# empties it and returns 1, and the caller turns that into `no-bun`.
retroloop_find_bun() {
  local candidate entry
  local -a dirs=()
  RETROLOOP_BUN_PATH=''

  # 1 · named outright, for a Bun no list can know about.
  retroloop_bun_ok "${RETROLOOP_BUN:-}" && return 0

  # 2 · the shell's own lookup, which is right whenever it answers at all.
  candidate="$(command -v bun 2>/dev/null)" || candidate=''
  retroloop_bun_ok "$candidate" && return 0

  # 3 · Bun's own install folder: the variable its installer sets when it was
  # sent somewhere else, then the default place under the home folder.
  if [ -n "${BUN_INSTALL:-}" ]; then
    retroloop_bun_ok "${BUN_INSTALL%/}/bin/bun" && return 0
  fi
  if [ -n "${HOME:-}" ]; then
    retroloop_bun_ok "${HOME%/}/.bun/bin/bun" && return 0
  fi

  # 4 · the fixed folders, Homebrew's and the system's.
  local IFS=':'
  read -r -a dirs <<<"${RETROLOOP_BUN_DIRS-$RETROLOOP_BUN_DIRS_DEFAULT}"
  for entry in ${dirs[@]+"${dirs[@]}"}; do
    [ -n "$entry" ] || continue
    retroloop_bun_ok "${entry%/}/bun" && return 0
  done

  RETROLOOP_BUN_PATH=''
  return 1
}

# The command that runs a .ts entry: Bun's full path and the file, never the
# bare word. Returns 1 when there is no Bun to run it with, which is the one
# case the caller has to tell apart from "no app here".
retroloop_cli_bun_run() { # <path to a .ts CLI entry>
  retroloop_find_bun || return 1
  RETROLOOP_CLI=("$RETROLOOP_BUN_PATH" "$1")
  return 0
}

# A hint — $RETROLOOP_APP — reads three ways: an app checkout directory, a .ts
# CLI entry, or an executable. Anything else is a miss, and a miss falls
# through to the next step; a bad hint must never abort a session start.
#
# Three answers: 0 a command, 1 nothing here, 2 an app is here but there is no
# Bun to run it with — a real app, found, and unrunnable, which reads to a
# human as a different sentence from either of the others.
retroloop_cli_from_hint() {
  local hint="${1:-}"
  [ -n "$hint" ] || return 1
  while [ "${#hint}" -gt 1 ] && [ "${hint%/}" != "$hint" ]; do hint="${hint%/}"; done

  if [ -d "$hint" ]; then
    [ -f "$hint/apps/cli/src/bin.ts" ] || return 1
    retroloop_cli_bun_run "$hint/apps/cli/src/bin.ts" || return 2
    return 0
  fi
  case "$hint" in
    *.ts)
      [ -f "$hint" ] || return 1
      retroloop_cli_bun_run "$hint" || return 2
      return 0
      ;;
  esac
  if [ -f "$hint" ] && [ -x "$hint" ]; then
    RETROLOOP_CLI=("$hint")
    return 0
  fi
  return 1
}

# $WATCH_REVIEW_CLI keeps the semantics it shipped with: a whole command
# string, split on whitespace, nothing checked for existence. All whitespace is
# no command at all — and running an empty command would arm nothing quietly,
# which is the failure the finish watch exists to remove.
retroloop_cli_from_command() {
  local -a words=()
  read -r -a words <<<"${1:-}"
  [ "${#words[@]}" -gt 0 ] || return 1
  RETROLOOP_CLI=("${words[@]}")
  return 0
}

# Is this PATH hit the command the plugin ships? It is if the marker file sits
# beside it — and a marker beside the file a symlink points at counts too, so
# linking the shipped command onto a PATH directory does not defeat the guard.
# The judgment is on the resolved path, never on the name: a user's own
# `retroloop` is still the answer that outranks everything.
retroloop_cli_is_shipped() { # <path to a retroloop found on PATH>
  local p="${1:-}" dir target hops=0
  [ -n "$p" ] || return 1
  while [ "$hops" -lt 8 ]; do
    dir="${p%/*}"
    [ "$dir" = "$p" ] && dir='.'
    [ -f "$dir/.retroloop-bin" ] && return 0
    [ -L "$p" ] || return 1
    target="$(readlink "$p" 2>/dev/null)" || return 1
    [ -n "$target" ] || return 1
    case "$target" in
      /*) p="$target" ;;
      *) p="$dir/$target" ;;
    esac
    hops=$((hops + 1))
  done
  return 1
}

# The whole PATH rung: the first `retroloop` along PATH that is not the command
# the plugin ships. Walked by hand, because `command -v` returns only the first
# `retroloop` of any kind and the shipped one is nearly always it — asking the
# shell and then refusing its answer would end the rung on the shipped command
# and never reach a user's own. Fills RETROLOOP_CLI and returns 0 on a hit.
retroloop_cli_on_path() {
  local IFS=':' entry candidate found
  local -a entries=()
  read -r -a entries <<<"${PATH:-}"
  for entry in ${entries[@]+"${entries[@]}"}; do
    # An empty PATH entry means the working directory, as it does to the shell.
    [ -n "$entry" ] || entry='.'
    candidate="$entry/retroloop"
    [ -f "$candidate" ] && [ -x "$candidate" ] || continue
    retroloop_cli_is_shipped "$candidate" && continue
    RETROLOOP_CLI=("$candidate")
    return 0
  done

  # The shell's own answer as a backstop, for anything the walk cannot see.
  found="$(command -v retroloop 2>/dev/null)" || return 1
  [ -n "$found" ] || return 1
  retroloop_cli_is_shipped "$found" && return 1
  RETROLOOP_CLI=("$found")
  return 0
}

# The root everything Retroloop keeps lives under: $RETROLOOP_HOME, else
# ~/.retroloop. Callers that print the root to a human want the tilde back, so
# this returns the expanded path and the printing is theirs.
retroloop_root() {
  printf '%s' "${RETROLOOP_HOME:-${HOME:-}/.retroloop}"
}

# retroloop_resolve_cli [<repo root>]
retroloop_resolve_cli() {
  local repo_root="${1:-}"
  local root="${RETROLOOP_HOME:-${HOME:-}/.retroloop}"
  # The hint's answer, read off a command that is ALLOWED to fail: under
  # `set -e` a bare call that returns 2 ends the caller's shell right here,
  # and the rungs below would never be walked.
  local hint_rc=0
  # An app was found somewhere and there was no Bun to run it with. It does not
  # end the walk — a later rung may answer with something that needs no Bun —
  # but if nothing else answers, this is what the miss is called.
  local no_bun=0

  RETROLOOP_CLI=()
  RETROLOOP_CLI_SOURCE=''
  RETROLOOP_CLI_MISS=''
  RETROLOOP_BUN_PATH=''

  # 1 · an installed binary is the user's own answer; nothing outranks it —
  # except the command this plugin ships, which is this file's own caller and
  # is always on PATH. Answering with that one is a command that runs itself.
  # So the walk steps over the shipped command and keeps going down PATH; only
  # a PATH with no other `retroloop` on it falls through to step 2.
  if retroloop_cli_on_path; then
    RETROLOOP_CLI_SOURCE=path
    return 0
  fi

  # 2 · the environment, for this shell only.
  if [ -n "${RETROLOOP_APP:-}" ]; then
    hint_rc=0
    retroloop_cli_from_hint "$RETROLOOP_APP" || hint_rc=$?
    case "$hint_rc" in
      0)
        RETROLOOP_CLI_SOURCE=env
        return 0
        ;;
      2) no_bun=1 ;;
    esac
  fi
  # The one rung nothing is checked on: a whole command string the user wrote.
  # Its contract is that it is taken as given, Bun and all.
  if [ -n "${WATCH_REVIEW_CLI:-}" ] && retroloop_cli_from_command "$WATCH_REVIEW_CLI"; then
    RETROLOOP_CLI_SOURCE=env
    return 0
  fi

  # 3 · the one place setup puts the app, inside the one root.
  if [ -f "$root/apps/retroloop/apps/cli/src/bin.ts" ]; then
    if retroloop_cli_bun_run "$root/apps/retroloop/apps/cli/src/bin.ts"; then
      RETROLOOP_CLI_SOURCE=default
      return 0
    fi
    no_bun=1
  fi

  # 4 · run from inside an app checkout, for a caller that knows its repo.
  if [ -n "$repo_root" ] && [ -f "$repo_root/apps/cli/src/bin.ts" ]; then
    if retroloop_cli_bun_run "$repo_root/apps/cli/src/bin.ts"; then
      RETROLOOP_CLI_SOURCE=repo
      return 0
    fi
    no_bun=1
  fi

  # Nothing answered. Say which of the two is missing: handing back a word that
  # will fail later is what made this failure arrive far from its cause.
  RETROLOOP_CLI=()
  RETROLOOP_CLI_SOURCE=''
  RETROLOOP_BUN_PATH=''
  if [ "$no_bun" -eq 1 ]; then
    RETROLOOP_CLI_MISS=no-bun
  else
    RETROLOOP_CLI_MISS=none
  fi
  return 1
}
