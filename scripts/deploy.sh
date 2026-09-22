#!/usr/bin/env bash
#
# Release a personalization plugin — the fixes are written, this is how they
# reach the human's sessions.
#
#   deploy.sh [--no-update] <plugin dir> <record id>...
#
# One command, because a release that takes five is a release that ships at
# four. It bumps the patch number, commits the working tree with the records it
# carries named in the subject, backs the plugin up if it has a remote, tells
# Claude Code to update, and then CHECKS that the update landed on the version
# it just wrote.
#
# The check is the point. A plugin's version is the only signal Claude Code has
# that anything changed, so a deploy that bumps and commits but never reaches
# the running Claude Code looks exactly like one that worked — and the fix
# silently never runs. A mismatch here is a failure, said out loud, with the
# reassurance that the commit itself is safe.
#
# Every step that fails stops the release and says which one, on stderr,
# non-zero. The last line on success is for the human, and it is the only thing
# they have to act on.

set -u

HERE="${BASH_SOURCE[0]%/*}"

# The local marketplace setup creates: one folder, every plugin the loop ever
# builds for this person.
MARKETPLACE='my-marketplace'

die() {
  printf 'deploy: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
deploy.sh — release a personalization plugin.

Usage:
  deploy.sh [--no-update] <plugin dir> <record id>...

`--no-update` does the bump, the commit and the backup push, but skips
`claude plugin update` and prints the command it would have run. It is for a
rehearsal against a scratch plugin, where a real update would move the pin of
a plugin the rehearsal does not own; a release for real never passes it.

The record ids are the retrospective records this release carries; they go in
the commit subject, so the plugin's history reads as the history of the
frictions it answers. At least one is required — a release that cannot say what
it carries is a release nobody can audit later.

  deploy.sh ~/.retroloop/plugins/my r-12 r-14
USAGE
  exit 2
}

NO_UPDATE=0
if [ "${1:-}" = '--no-update' ]; then
  NO_UPDATE=1
  shift
fi

[ $# -ge 2 ] || usage

DIR="$1"
shift

[ -d "$DIR" ] || die "no plugin directory at $DIR"
MANIFEST="$DIR/.claude-plugin/plugin.json"
[ -f "$MANIFEST" ] || die "no plugin manifest at $MANIFEST"

# ── what is being released ───────────────────────────────────────────────────
NAME="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n1)"
[ -n "$NAME" ] || die "no \"name\" in $MANIFEST"

OLD="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n1)"
[ -n "$OLD" ] || die "no \"version\" in $MANIFEST"

major="${OLD%%.*}"
rest="${OLD#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"
case "$major$minor$patch" in
  '' | *[!0-9]*) die "version \"$OLD\" is not <major>.<minor>.<patch>" ;;
esac
NEW="$major.$minor.$((patch + 1))"

# The bump is silent: the human asked for a fix, not for a version number.
tmp="$MANIFEST.deploy.$$"
sed 's/\("version"[[:space:]]*:[[:space:]]*\)"'"$OLD"'"/\1"'"$NEW"'"/' "$MANIFEST" >"$tmp" ||
  die 'could not write the bumped manifest'
grep -q "\"$NEW\"" "$tmp" || {
  rm -f "$tmp"
  die "the bump to $NEW did not take"
}
mv "$tmp" "$MANIFEST" || die 'could not replace the manifest'

# ── the commit ───────────────────────────────────────────────────────────────
# The records ride in the subject: `release 0.1.4 — #r-12 #r-14`. A `#` the
# caller already typed is not doubled.
refs=''
for id in "$@"; do
  [ -n "$id" ] || continue
  id="$(printf '%s' "$id" | sed 's/^#//')"
  refs="$refs #$id"
done
[ -n "$refs" ] || usage

MESSAGE="release $NEW —$refs"

git -C "$DIR" add -A || die "git add failed in $DIR"
git -C "$DIR" commit -qm "$MESSAGE" ||
  die 'git commit failed — nothing staged, or a hook refused it'

# ── the backup, if there is one ──────────────────────────────────────────────
# A remote is the human's own choice; setup does not ask. With one this pushes;
# without one it does nothing and says nothing, and either way it cannot fail
# the release.
bash "$HERE/plugin-push.sh" "$DIR"

# ── the deploy, and the proof it landed ──────────────────────────────────────
# A rehearsal stops here and says so: the commit is real, the update is not,
# and the line makes that impossible to mistake for a release.
if [ "$NO_UPDATE" -eq 1 ]; then
  printf 'Plugin committed as %s, not released: skipped `claude plugin update %s@%s --json -y` (--no-update).\n' "$NEW" "$NAME" "$MARKETPLACE"
  exit 0
fi

out="$(claude plugin update "$NAME@$MARKETPLACE" --json -y 2>&1)" ||
  die "claude plugin update $NAME@$MARKETPLACE failed — the commit stands, the update did not land: $out"

printf '%s' "$out" | grep -q '"outcome"[[:space:]]*:[[:space:]]*"ok"' ||
  die "the update did not report ok — the commit stands, the update did not land: $out"

landed="$(printf '%s' "$out" | sed -n 's/.*"newVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
[ "$landed" = "$NEW" ] ||
  die "the update landed on [$landed], not the $NEW just released — the commit stands, the update did not land: $out"

printf 'Plugin released as %s. In any Claude Code session that is already open, type /reload-plugins once. New sessions need nothing.\n' "$NEW"
