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
# app anywhere else — a documented choice the setup skill offers — was told
# "Retroloop is installed but not set up" at every session start, forever. One
# resolver, one answer, every caller.
#
# On success it fills:
#   RETROLOOP_CLI          the command as an array (command + args)
#   RETROLOOP_CLI_SOURCE   path · env · pointer · default · repo
# and returns 0. On a total miss RETROLOOP_CLI is empty and it returns 1.
# RETROLOOP_CLI_POINTER always names the pointer file it would consult.
#
# Resolution order, first hit wins:
#   1 path     `retroloop` on PATH
#   2 env      $RETROLOOP_APP, then $WATCH_REVIEW_CLI (the older spelling)
#   3 pointer  <home>/app-path, written by /retroloop:setup, where <home> is
#              $RETROLOOP_HOME, else $RETRO_HOME, else ~/.ai-team/retro
#   4 default  ~/Developer/retroloop-app/apps/cli/src/bin.ts
#   5 repo     <repo root>/apps/cli/src/bin.ts, for a caller that passes one
#              (the finish watch does; the hook does not, so no `git` runs at
#              session start)
#
# It runs at EVERY session start, so it costs one `command -v` and a handful of
# file tests: no network, no subshell, no `git`, no `bun`. It never runs the
# CLI it finds — it only decides what the command would be. It is safe under
# `set -u`, `set -e` and `set -o pipefail`.

RETROLOOP_CLI=()
RETROLOOP_CLI_SOURCE=''
RETROLOOP_CLI_POINTER=''
RETROLOOP_CLI_POINTER_LINE=''

# A hint — $RETROLOOP_APP, or the pointer file's line — reads three ways:
# an app checkout directory, a .ts CLI entry, or an executable. Anything else
# is a miss, and a miss falls through to the next step; a bad hint must never
# abort a session start.
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

# Reads the pointer file's single line into RETROLOOP_CLI_POINTER_LINE, trimmed
# of surrounding whitespace and a trailing CR. Returns 1 when the file is
# missing or the line is empty. No subshell: this is on the session-start path.
retroloop_cli_read_pointer() {
  RETROLOOP_CLI_POINTER_LINE=''
  [ -n "$RETROLOOP_CLI_POINTER" ] || return 1
  [ -f "$RETROLOOP_CLI_POINTER" ] || return 1
  IFS=$' \t\r\n' read -r RETROLOOP_CLI_POINTER_LINE <"$RETROLOOP_CLI_POINTER" || :
  [ -n "$RETROLOOP_CLI_POINTER_LINE" ] || return 1
  return 0
}

# retroloop_resolve_cli [<repo root>]
retroloop_resolve_cli() {
  local repo_root="${1:-}"
  local home_dir="${HOME:-}"
  local found=''

  RETROLOOP_CLI=()
  RETROLOOP_CLI_SOURCE=''
  RETROLOOP_CLI_POINTER="${RETROLOOP_HOME:-${RETRO_HOME:-$home_dir/.ai-team/retro}}/app-path"
  RETROLOOP_CLI_POINTER_LINE=''

  # 1 · an installed binary is the user's own answer; nothing outranks it.
  if found="$(command -v retroloop 2>/dev/null)" && [ -n "$found" ]; then
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

  # 3 · the pointer file: where setup recorded the install, once, for good.
  if retroloop_cli_read_pointer && retroloop_cli_from_hint "$RETROLOOP_CLI_POINTER_LINE"; then
    RETROLOOP_CLI_SOURCE=pointer
    return 0
  fi

  # 4 · where the app has always gone by default.
  if [ -f "$home_dir/Developer/retroloop-app/apps/cli/src/bin.ts" ]; then
    RETROLOOP_CLI=(bun "$home_dir/Developer/retroloop-app/apps/cli/src/bin.ts")
    RETROLOOP_CLI_SOURCE=default
    return 0
  fi

  # 5 · run from inside an app checkout, for a caller that knows its repo.
  if [ -n "$repo_root" ] && [ -f "$repo_root/apps/cli/src/bin.ts" ]; then
    RETROLOOP_CLI=(bun "$repo_root/apps/cli/src/bin.ts")
    RETROLOOP_CLI_SOURCE=repo
    return 0
  fi

  RETROLOOP_CLI=()
  RETROLOOP_CLI_SOURCE=''
  return 1
}
