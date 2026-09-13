#!/usr/bin/env bash
#
# Tell an open session when the plugin it is running has been left behind.
#
#   version-drift.sh                 check once, print a line per plugin behind
#   version-drift.sh --watch <secs>  keep checking, every <secs> seconds
#
# A Claude Code session loads a plugin when it starts and never looks again. So
# when the loop releases a new version of a personalization plugin, every
# session already open goes on running the old one — invisibly, until someone
# types /reload-plugins. This is the thing that says so.
#
# What it compares, for every plugin in the local marketplace:
#
#   the PIN     the version Claude Code recorded when it installed the plugin,
#               in its own installed-plugins file
#   the SOURCE  the version in the plugin folder's manifest, which is what the
#               last release wrote
#
# In watch mode the pin AT ARM TIME is remembered as well, because that is the
# version this session actually loaded: a pin that has moved since is the
# clearest possible evidence that the session is behind. Each distinct line is
# printed once per run — a nag repeated every minute is a nag nobody reads.
#
# It prints nothing at all when there is nothing to say, when a file it needs
# is missing, or when a plugin is not installed on this machine, and it always
# exits 0. A monitor that fails is a monitor that gets removed.
#
# NO BRACE-WRAPPED VARIABLES ANYWHERE IN THIS FILE, and no relative paths. It
# is started from a plugin monitor, whose command line is expanded before the
# shell ever sees it — a brace form is consumed at that point and arrives
# empty — and it runs with whatever working directory the monitor happened to
# have. Both rules are enforced by tests/version-drift.test.sh.
#
# Tools: bash, awk, sed, tr, head, cut, sleep. Nothing installed, nothing that
# a fresh macOS does not already have.

set -u

MARKETPLACE_FILE='/plugins/.claude-plugin/marketplace.json'

usage() {
  cat >&2 <<'USAGE'
version-drift.sh — say when an open session is running an outdated plugin.

Usage:
  version-drift.sh                      check once and exit
  version-drift.sh --watch <seconds>    check every <seconds>, forever
  version-drift.sh --watch <s> --rounds <n>   ... for <n> rounds, then exit
  version-drift.sh help                 this text

It prints one line per plugin whose installed version differs from the version
in its source folder, and nothing otherwise. It always exits 0.

Environment:
  RETROLOOP_HOME      the Retroloop root; the default is ~/.retroloop
  CLAUDE_CONFIG_DIR   where Claude Code keeps its own state; default ~/.claude
USAGE
  exit 2
}

# ── the environment, read without brace forms ────────────────────────────────
# `set -u` and no braces means an optional variable cannot be read with a
# default; `declare -p` answers whether it is set without expanding it.
env_value() { # <variable name>
  declare -p "$1" >/dev/null 2>&1 || return 0
  eval 'printf "%s" "$'"$1"'"'
}

home_dir() {
  local h
  h="$(env_value HOME)"
  printf '%s' "$h"
}

# Everything Retroloop keeps lives under one root, and the marketplace is the
# plugins folder inside it.
root_dir() {
  local r
  r="$(env_value RETROLOOP_HOME)"
  [ -n "$r" ] || r="$(home_dir)/.retroloop"
  printf '%s' "$r"
}

# Where Claude Code records what it installed, and at which version.
pins_file() {
  local d
  d="$(env_value CLAUDE_CONFIG_DIR)"
  [ -n "$d" ] || d="$(home_dir)/.claude"
  printf '%s/plugins/installed_plugins.json' "$d"
}

# ── reading the three files ──────────────────────────────────────────────────
# All three are JSON, and this has no JSON parser: awk over the flattened text
# is enough for the three flat facts needed, and depends on nothing installed.

# The marketplace's own name — the first "name" before the plugin list, which
# is the half of "<plugin>@<marketplace>" that Claude Code keys installs by.
market_name() { # <marketplace file>
  tr -d '\n' <"$1" | awk '
    {
      s = $0
      i = index(s, "\"plugins\"")
      if (i > 0) s = substr(s, 1, i)
      if (match(s, /"name"[ \t]*:[ \t]*"[^"]*"/)) {
        v = substr(s, RSTART, RLENGTH)
        sub(/^"name"[ \t]*:[ \t]*"/, "", v)
        sub(/"$/, "", v)
        print v
      }
    }'
}

# Every entry in the plugin list, as "<name> <source>".
market_plugins() { # <marketplace file>
  tr -d '\n' <"$1" | awk '
    function field(r, key,   v) {
      if (!match(r, "\"" key "\"[ \t]*:[ \t]*\"[^\"]*\"")) return ""
      v = substr(r, RSTART, RLENGTH)
      sub(/^"[^"]*"[ \t]*:[ \t]*"/, "", v)
      sub(/"$/, "", v)
      return v
    }
    {
      s = $0
      i = index(s, "\"plugins\"")
      if (i == 0) exit
      s = substr(s, i)
      n = split(s, entry, "}")
      for (k = 1; k <= n; k++) {
        name = field(entry[k], "name")
        src = field(entry[k], "source")
        if (name != "" && src != "") print name " " src
      }
    }'
}

# The pinned version: the first "version" inside the array Claude Code keys by
# "<plugin>@<marketplace>". Nothing at all when this machine never installed it.
pin_version() { # <pins file> <key>
  [ -f "$1" ] || return 0
  tr -d '\n' <"$1" | awk -v key="$2" '
    {
      s = $0
      k = "\"" key "\""
      i = index(s, k)
      if (i == 0) exit
      s = substr(s, i + length(k))
      j = index(s, "]")
      if (j > 0) s = substr(s, 1, j)
      if (match(s, /"version"[ \t]*:[ \t]*"[^"]*"/)) {
        v = substr(s, RSTART, RLENGTH)
        sub(/^"version"[ \t]*:[ \t]*"/, "", v)
        sub(/"$/, "", v)
        print v
      }
    }'
}

# The version the last release wrote into the plugin's own manifest.
source_version() { # <plugin directory>
  local manifest="$1/.claude-plugin/plugin.json"
  [ -f "$manifest" ] || return 0
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n1
}

# ── the state of every plugin, in one pass ───────────────────────────────────
# One line per plugin whose pin AND source are both known: "<key> <pin> <src>".
# A plugin missing either is not drift — it is a plugin this machine does not
# have, or a folder no release has touched.
scan() {
  local root market pins name entries pname psrc dir pin src
  root="$(root_dir)"
  market="$root$MARKETPLACE_FILE"
  [ -f "$market" ] || return 0
  pins="$(pins_file)"
  [ -f "$pins" ] || return 0
  name="$(market_name "$market")"
  [ -n "$name" ] || return 0

  entries="$(market_plugins "$market")"
  [ -n "$entries" ] || return 0

  printf '%s\n' "$entries" | while read -r pname psrc; do
    [ -n "$pname" ] || continue
    dir="$root/plugins/$(printf '%s' "$psrc" | sed 's#^\./##')"
    pin="$(pin_version "$pins" "$pname@$name")"
    [ -n "$pin" ] || continue
    src="$(source_version "$dir")"
    [ -n "$src" ] || continue
    printf '%s %s %s\n' "$pname@$name" "$pin" "$src"
  done
}

# The one line a human can act on: what happened, and the single thing to do
# about it. Identical to what a release prints, because it is the same news
# arriving late.
drift_line() { # <key> <pin> <source>
  printf '%s: installed %s, source %s. Plugin released as %s. In any Claude Code session that is already open, type /reload-plugins once. New sessions need nothing.\n' "$1" "$2" "$3" "$3"
}

# ── arguments ────────────────────────────────────────────────────────────────
MODE='once'
SECONDS_BETWEEN=60
ROUNDS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    help | --help | -h) usage ;;
    --watch)
      [ "$#" -ge 2 ] || usage
      MODE='watch'
      SECONDS_BETWEEN="$2"
      shift 2
      ;;
    --rounds)
      [ "$#" -ge 2 ] || usage
      ROUNDS="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

case "$SECONDS_BETWEEN" in
  '' | *[!0-9]*) usage ;;
esac
case "$ROUNDS" in
  '' | *[!0-9]*) usage ;;
esac

# ── one check ────────────────────────────────────────────────────────────────
if [ "$MODE" = 'once' ]; then
  scan | while read -r key pin src; do
    [ "$pin" = "$src" ] || drift_line "$key" "$pin" "$src"
  done
  exit 0
fi

# ── the watch ────────────────────────────────────────────────────────────────
# The pin as it stands now is the version this session loaded. Remember it: a
# session is behind the moment that pin moves, whether or not the source has
# moved too.
SNAPSHOT="$(scan)"
SAID=''
ROUND=0

while :; do
  sleep "$SECONDS_BETWEEN"
  ROUND=$((ROUND + 1))

  while read -r key pin src; do
    [ -n "$key" ] || continue
    was="$(printf '%s\n' "$SNAPSHOT" | awk -v k="$key" '$1 == k { print $2; exit }')"
    behind='no'
    [ "$pin" = "$src" ] || behind='yes'
    if [ -n "$was" ] && [ "$pin" != "$was" ]; then behind='yes'; fi
    [ "$behind" = 'yes' ] || continue

    line="$(drift_line "$key" "$pin" "$src")"
    case "$SAID" in
      *"$line"*) ;;
      *)
        printf '%s\n' "$line"
        SAID="$SAID$line"$'\n'
        ;;
    esac
  done <<EOF
$(scan)
EOF

  if [ "$ROUNDS" -gt 0 ] && [ "$ROUND" -ge "$ROUNDS" ]; then
    break
  fi
done

exit 0
