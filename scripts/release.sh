#!/usr/bin/env bash
#
# Release THIS plugin — the Retroloop plugin itself, for its owner. One
# command, because a release that takes five is a release that ships at four.
#
#   scripts/release.sh <what changed, in words>
#
# It bumps the patch number, commits everything in the working tree, pushes,
# tells Claude Code to update, and verifies the update actually landed on the
# version it just wrote. The verification is the point: `plugin.json`'s version
# is the only update signal there is, so a release that bumps but does not
# deploy looks exactly like a release that worked.
#
# This is the OWNER's script for the Retroloop plugin. A user's own
# personalization plugin is released by the manager through scripts/deploy.sh,
# which bumps silently and pushes through scripts/plugin-push.sh.
#
# Any step failing stops the release and says which one, loudly and non-zero.

set -u

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
MANIFEST="$ROOT/.claude-plugin/plugin.json"
PLUGIN='retroloop@retroloop'

die() {
  printf 'release: %s\n' "$1" >&2
  exit 1
}

[ -f "$MANIFEST" ] || die "no plugin manifest at $MANIFEST"

# ── the bump ─────────────────────────────────────────────────────────────────
old="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MANIFEST" | head -n1)"
[ -n "$old" ] || die "no \"version\" in $MANIFEST"

major="${old%%.*}"
rest="${old#*.}"
minor="${rest%%.*}"
patch="${rest#*.}"
case "$major$minor$patch" in
  '' | *[!0-9]*) die "version \"$old\" is not <major>.<minor>.<patch>" ;;
esac
new="$major.$minor.$((patch + 1))"

tmp="$MANIFEST.release.$$"
sed 's/\("version"[[:space:]]*:[[:space:]]*\)"'"$old"'"/\1"'"$new"'"/' "$MANIFEST" >"$tmp" || die 'could not write the bumped manifest'
grep -q "\"$new\"" "$tmp" || { rm -f "$tmp"; die "the bump to $new did not take"; }
mv "$tmp" "$MANIFEST" || die 'could not replace the manifest'

# ── the commit ───────────────────────────────────────────────────────────────
if [ "$#" -gt 0 ]; then
  message="release $new — $*"
else
  message="release $new"
fi

git -C "$ROOT" add -A || die 'git add failed'
git -C "$ROOT" commit -qm "$message" || die 'git commit failed — nothing staged, or a hook refused it'
git -C "$ROOT" push -q || die "git push failed — $new is committed locally but not published"

# ── the deploy, and the proof it landed ──────────────────────────────────────
out="$(claude plugin update "$PLUGIN" --json -y 2>&1)" ||
  die "claude plugin update $PLUGIN failed: $out"

printf '%s' "$out" | grep -q '"outcome"[[:space:]]*:[[:space:]]*"ok"' ||
  die "the update did not report ok: $out"

landed="$(printf '%s' "$out" | sed -n 's/.*"newVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
[ "$landed" = "$new" ] ||
  die "the update landed on [$landed], not the $new just released: $out"

printf 'Retroloop released as %s. In any Claude Code session that is already open, type /reload-plugins once. New sessions need nothing.\n' "$new"
