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
# Then there was a pointer file — a line on disk naming the install — to cover
# the user who chose their own directory. It is gone: Retroloop now has ONE
# root, `~/.retroloop`, and the app has one place inside it,
# `<root>/apps/retroloop`. A fixed place needs no record of where it is. The
# user who still wants the app elsewhere sets `RETROLOOP_APP`, which is a
# statement about this shell and needs no file to stay true.
#
# On success it fills:
#   RETROLOOP_CLI          the command as an array (command + args)
#   RETROLOOP_CLI_SOURCE   path · env · default · repo
# and returns 0. On a total miss RETROLOOP_CLI is empty and it returns 1.
#
# Resolution order, first hit wins:
#   1 path     `retroloop` on PATH, unless it is the command this plugin ships
#   2 env      $RETROLOOP_APP, then $WATCH_REVIEW_CLI (the older spelling)
#   3 default  <root>/apps/retroloop/apps/cli/src/bin.ts, where <root> is
#              $RETROLOOP_HOME, else ~/.retroloop
#   4 repo     <repo root>/apps/cli/src/bin.ts, for a caller that passes one
#              (the finish watch does; the hook does not, so no `git` runs at
#              session start)
#
# `RETRO_HOME` is retired and is read nowhere: a stale one in someone's profile
# must not be able to move the answer.
#
# It runs at EVERY session start, so it costs one `command -v` and a handful of
# file tests: no network, no `git`, no `bun`. It never runs the CLI it finds —
# it only decides what the command would be. It is safe under `set -u`,
# `set -e` and `set -o pipefail`.

RETROLOOP_CLI=()
RETROLOOP_CLI_SOURCE=''

# A hint — $RETROLOOP_APP — reads three ways: an app checkout directory, a .ts
# CLI entry, or an executable. Anything else is a miss, and a miss falls
# through to the next step; a bad hint must never abort a session start.
retroloop_cli_from_hint() {
  local hint="${1:-}"
  [ -n "$hint" ] || return 1
  while [ "${#hint}" -gt 1 ] && [ "${hint%/}" != "$hint" ]; do hint="${hint%/}"; done

  if [ -d "$hint" ]; then
    [ -f "$hint/apps/cli/src/bin.ts" ] || return 1
    RETROLOOP_CLI=(bun "$hint/apps/cli/src/bin.ts")
    return 0
  fi
  case "$hint" in
    *.ts)
      [ -f "$hint" ] || return 1
      RETROLOOP_CLI=(bun "$hint")
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
  local found=''

  RETROLOOP_CLI=()
  RETROLOOP_CLI_SOURCE=''

  # 1 · an installed binary is the user's own answer; nothing outranks it —
  # except the command this plugin ships, which is this file's own caller and
  # is always on PATH. Answering with that one is a command that runs itself.
  if found="$(command -v retroloop 2>/dev/null)" && [ -n "$found" ] &&
    ! retroloop_cli_is_shipped "$found"; then
    RETROLOOP_CLI=("$found")
    RETROLOOP_CLI_SOURCE=path
    return 0
  fi

  # 2 · the environment, for this shell only.
  if [ -n "${RETROLOOP_APP:-}" ] && retroloop_cli_from_hint "$RETROLOOP_APP"; then
    RETROLOOP_CLI_SOURCE=env
    return 0
  fi
  if [ -n "${WATCH_REVIEW_CLI:-}" ] && retroloop_cli_from_command "$WATCH_REVIEW_CLI"; then
    RETROLOOP_CLI_SOURCE=env
    return 0
  fi

  # 3 · the one place setup puts the app, inside the one root.
  if [ -f "$root/apps/retroloop/apps/cli/src/bin.ts" ]; then
    RETROLOOP_CLI=(bun "$root/apps/retroloop/apps/cli/src/bin.ts")
    RETROLOOP_CLI_SOURCE=default
    return 0
  fi

  # 4 · run from inside an app checkout, for a caller that knows its repo.
  if [ -n "$repo_root" ] && [ -f "$repo_root/apps/cli/src/bin.ts" ]; then
    RETROLOOP_CLI=(bun "$repo_root/apps/cli/src/bin.ts")
    RETROLOOP_CLI_SOURCE=repo
    return 0
  fi

  RETROLOOP_CLI=()
  RETROLOOP_CLI_SOURCE=''
  return 1
}
