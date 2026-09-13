#!/usr/bin/env bash
#
# Make sure the resolve lane has a manager — and never two.
#
#   ensure-manager.sh
#
# The manager is one long-lived Claude Code background session, running in the
# user's personalization plugin, that carries approved fixes from the review
# through to a release. This script is the only thing that starts it. It takes
# no arguments and it is safe to run at any time, from anywhere, as often as
# you like: it reports the manager that is already up, resumes the one that
# stopped, or starts a fresh one, and two callers racing each other still leave
# exactly one manager behind.
#
# What it prints on stdout is always one line:
#
#   running <session id>              a manager is up — this is the one
#   setup has not run; no manager     there is no personalization plugin yet
#
# Anything else it has to say goes to stderr, prefixed `ensure-manager:`, and
# comes with a non-zero exit.
#
# The environment it reads: RETROLOOP_HOME (else ~/.retroloop) for the root,
# and PATH for `claude`. It writes exactly one thing, the lock it holds while
# launching, under <root>/agents/manager/ — and removes it on every exit.

set -u

MANAGER_NAME='retroloop-manager'
DEFAULT_MODEL='fable'

# How long a caller that loses the race waits for the winner, how old a lock
# has to be before it is assumed abandoned, and how long a launch is given to
# show up in the session list. Seconds, all three.
LOCK_WAIT=60
LOCK_STALE=120
APPEAR_WAIT=15

say() { printf 'ensure-manager: %s\n' "$1" >&2; }

die() {
  say "$1"
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
ensure-manager.sh — make sure the resolve lane has a manager, and never two.

Usage:
  ensure-manager.sh        report the manager, or start one
  ensure-manager.sh help   this text

It takes no arguments and is safe to run repeatedly and concurrently. On stdout
it prints `running <session id>` when a manager is up — which includes the one
it just started — or `setup has not run; no manager` when there is no
personalization plugin to run one in.

Environment:
  RETROLOOP_HOME   the Retroloop root; the default is ~/.retroloop
USAGE
  exit 2
}

case "${1:-}" in
  help | --help | -h) usage ;;
  '') ;;
  *) usage ;;
esac

# ── where everything is ──────────────────────────────────────────────────────
# The root is decided in one place for the whole plugin, and this script asks
# that place rather than spelling out ~/.retroloop again.
RESOLVER="${BASH_SOURCE[0]%/*}/resolve-cli.sh"
[ -f "$RESOLVER" ] ||
  die "no resolver at $RESOLVER — this plugin checkout is incomplete."
# shellcheck source=resolve-cli.sh
. "$RESOLVER"

ROOT="$(retroloop_root)"
PLUGIN_DIR="$ROOT/plugins/my"

# No plugin, no manager, and no complaint: a machine where setup has not run is
# not a broken machine. This is the one path that starts nothing at all.
if [ ! -d "$PLUGIN_DIR" ]; then
  printf 'setup has not run; no manager\n'
  exit 0
fi

# A session's `cwd` is reported as the path the process actually has, which on
# macOS is the physical one (/private/var/…) while the configured path is very
# often the symlinked one (/var/…). Both spellings are the plugin, so both are
# compared.
PLUGIN_PHYS="$(cd "$PLUGIN_DIR" 2>/dev/null && pwd -P)"
[ -n "$PLUGIN_PHYS" ] || PLUGIN_PHYS="$PLUGIN_DIR"

command -v claude >/dev/null 2>&1 ||
  die 'no claude on PATH — the manager is a Claude Code background session, and there is nothing here to start one with.'

MANAGER_HOME="$ROOT/agents/manager"
mkdir -p "$MANAGER_HOME" 2>/dev/null ||
  die "could not make the manager's home at $MANAGER_HOME"

LOCK="$MANAGER_HOME/lock"
OWNER="$LOCK/owner"

# ── who is running ───────────────────────────────────────────────────────────
# `claude agents --json` prints a JSON array of flat objects. Reading it with
# awk rather than a JSON parser is deliberate: this runs on whatever bash and
# whatever tools a fresh macOS has, and depends on nothing installed. Key order
# and whitespace are free to vary; each `}` ends one session.
#
# A manager is a session with the manager's NAME running in the plugin's
# DIRECTORY. `status` and `state` are never read — a manager that is idle is
# still the manager. Live means listed without `--all`; stopped means listed
# only with it.
managers() { # [--all] → "<startedAt> <sessionId>" per manager, earliest first
  claude agents --json "$@" 2>/dev/null | awk \
    -v want="$MANAGER_NAME" -v c1="$PLUGIN_DIR" -v c2="$PLUGIN_PHYS" '
    BEGIN { RS = "}" }
    function str(s, key,   v) {
      if (!match(s, "\"" key "\"[ \t\r\n]*:[ \t\r\n]*\"[^\"]*\"")) return ""
      v = substr(s, RSTART, RLENGTH)
      sub(/^"[^"]*"[ \t\r\n]*:[ \t\r\n]*"/, "", v)
      sub(/"$/, "", v)
      return v
    }
    function num(s, key,   v) {
      if (!match(s, "\"" key "\"[ \t\r\n]*:[ \t\r\n]*[0-9]+")) return "0"
      v = substr(s, RSTART, RLENGTH)
      sub(/^.*:[ \t\r\n]*/, "", v)
      return v
    }
    {
      n = str($0, "name")
      c = str($0, "cwd")
      s = str($0, "sessionId")
      if (n == want && (c == c1 || c == c2) && s != "") print num($0, "startedAt") " " s
    }
  ' | sort -n
}

# Prints `running <id>` and returns 0 when a manager is up. More than one is
# not an error — the human is told, and the oldest is the answer, because a
# duplicate that just started is the one to close.
report_running() {
  local rows count ids first
  rows="$(managers)"
  [ -n "$rows" ] || return 1

  count="$(printf '%s\n' "$rows" | grep -c .)"
  first="$(printf '%s\n' "$rows" | head -n1 | cut -d' ' -f2)"
  if [ "$count" -gt 1 ]; then
    ids="$(printf '%s\n' "$rows" | cut -d' ' -f2 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    say "warning — $count managers running: $ids"
  fi
  printf 'running %s\n' "$first"
  return 0
}

# ── the lock ─────────────────────────────────────────────────────────────────
# `mkdir` either creates the directory or fails, in one step, with no window in
# between — which is the whole reason the lock is a directory and not a file.
HELD=''

release_lock() {
  [ -n "$HELD" ] && rm -rf "$HELD"
  return 0
}
trap release_lock EXIT

take_lock() {
  mkdir "$LOCK" 2>/dev/null || return 1
  HELD="$LOCK"
  printf 'pid=%s\nstarted=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$OWNER" 2>/dev/null
  return 0
}

owner_field() { # <key>
  [ -f "$OWNER" ] || return 0
  sed -n "s/^$1=//p" "$OWNER" 2>/dev/null | head -n1
}

# A lock whose owner is gone, or one nobody has touched for two minutes, is
# rubble from a killed run, not a claim. Either is enough to clear it: a launch
# takes seconds, so a lock that old cannot be a launch in progress.
lock_is_stale() {
  local pid now stamp
  pid="$(owner_field pid)"
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  now="$(date +%s 2>/dev/null)"
  stamp="$(date -r "$OWNER" +%s 2>/dev/null)"
  [ -n "$stamp" ] || stamp="$(date -r "$LOCK" +%s 2>/dev/null)"
  if [ -n "$now" ] && [ -n "$stamp" ] && [ "$((now - stamp))" -gt "$LOCK_STALE" ]; then
    return 0
  fi
  return 1
}

# ── the launch, and the resume ───────────────────────────────────────────────
# The model is the human's choice, recorded at setup in the plugin's own note
# as plain lines. A missing file or a missing line is not a problem worth
# stopping for: the default is the manager's model.
read_model() {
  local note="$PLUGIN_DIR/retroloop.md" model=''
  if [ -f "$note" ]; then
    model="$(sed -n 's/^[[:space:]]*model:[[:space:]]*\(.*\)$/\1/p' "$note" 2>/dev/null |
      head -n1 | sed 's/[[:space:]]*$//')"
  fi
  [ -n "$model" ] || model="$DEFAULT_MODEL"
  printf '%s' "$model"
}

# THE MANAGER'S LAUNCH LINE. It is written here, once, and nowhere else in this
# plugin, because it is the line most likely to need adjusting after a live
# check against Claude Code — and a command that appears twice gets fixed once.
launch_manager() { # <model> → the launch's own output; exits with its status
  CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1 claude \
    --bg \
    --name "$MANAGER_NAME" \
    --agent retroloop:manager \
    --permission-mode auto \
    --model "$1" \
    --settings '{"crossSessionInbound":"accept"}' \
    'start the resolve lane' 2>&1
}

# THE MANAGER'S RESUME LINE, for the same reason: one place, one spelling. A
# resumed manager keeps everything it already knows about the lane, so a
# stopped session is always preferred to a fresh one. No options besides the
# id and `--bg`: a background session keeps the options it was started with
# (name, permission mode, model, settings) and restores them on an in-place
# resume, while passing any option starts a COPY under a new id — which is
# exactly the second manager this script exists to prevent. The reap-disable
# variable is environment, not an option, so it is set again here.
resume_manager() { # <session id>
  CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1 claude \
    --resume "$1" \
    --bg \
    'resume the resolve lane' 2>&1
}

# A stopped manager leaves the wait it was holding behind as an orphan — a
# `review wait --any` process that answers to nobody. It is harmless, but it
# is a leak per restart, and the manager re-arms its wait on every start
# anyway. No manager is live at the moment this runs, so any such process is
# an orphan by definition.
reap_orphaned_waits() {
  pkill -f 'review wait --any' 2>/dev/null || true
}

# ── the run ──────────────────────────────────────────────────────────────────
# 1 · somebody else already did the work.
report_running && exit 0

# 2 · take the lock, or wait for whoever holds it.
if ! take_lock && lock_is_stale; then
  rm -rf "$LOCK"
  take_lock || true
fi

if [ -z "$HELD" ]; then
  waited=0
  while [ -z "$HELD" ]; do
    # The manager appearing is the outcome we are waiting for; the lock
    # clearing is only the second-best one.
    report_running && exit 0
    take_lock && break
    [ "$waited" -lt "$LOCK_WAIT" ] || break
    sleep 1
    waited=$((waited + 1))
  done
fi

if [ -z "$HELD" ]; then
  held_pid="$(owner_field pid)"
  held_since="$(owner_field started)"
  [ -n "$held_pid" ] || held_pid='?'
  [ -n "$held_since" ] || held_since='?'
  die "lock held by pid $held_pid since $held_since"
fi

# 3 · holding the lock, look once more: the wait above may have ended the
#     moment a launch finished.
report_running && exit 0

# 4 · resume the stopped manager, or start a new one. Nothing is live at this
#     point, so every manager `--all` knows about is a stopped one, and the
#     most recent of those is the lane's own history.
MODEL="$(read_model)"
STOPPED="$(managers --all | tail -n1 | cut -d' ' -f2)"

reap_orphaned_waits

if [ -n "$STOPPED" ]; then
  LAUNCH_OUT="$(cd "$PLUGIN_DIR" && resume_manager "$STOPPED")"
else
  LAUNCH_OUT="$(cd "$PLUGIN_DIR" && launch_manager "$MODEL")"
fi
LAUNCH_RC=$?
[ "$LAUNCH_RC" -eq 0 ] || die "launch failed — $LAUNCH_OUT"

# 5 · say which session it is. A background launch returns before its session
#     is listable, so the list is given a few seconds to catch up; the id on
#     the `backgrounded` line is the fallback, and silence is never one.
waited=0
while [ "$waited" -lt "$APPEAR_WAIT" ]; do
  if report_running; then
    exit 0
  fi
  sleep 1
  waited=$((waited + 1))
done

SHORT="$(printf '%s\n' "$LAUNCH_OUT" |
  awk -F' · ' '/^backgrounded/ { sub(/^[ \t]+/, "", $2); sub(/[ \t]+$/, "", $2); print $2; exit }')"
if [ -n "$SHORT" ]; then
  printf 'running %s\n' "$SHORT"
  exit 0
fi

die "the manager was started but never appeared in \`claude agents --json\` — it said: $LAUNCH_OUT"
