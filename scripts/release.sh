#!/usr/bin/env bash
# Prépare et publie une release :
#   - bump la version dans pubspec.yaml
#   - met à jour CHANGELOG.md (section de la version, régénérée si elle existe)
#   - commit, (re)crée le tag vX.Y.Z (supprime l'ancien local + distant)
#   - push la branche et le tag → déclenche le workflow GitHub (build APK + release)
#
# Usage : ./scripts/release.sh <version>   (ex: ./scripts/release.sh 1.2.0)
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: ./scripts/release.sh <version>   (ex: 1.2.0)" >&2
  exit 1
fi
if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Version invalide : $VERSION (attendu X.Y.Z)" >&2
  exit 1
fi

TAG="v$VERSION"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [ -n "$(git status --porcelain)" ]; then
  echo "Arbre de travail non propre — commit/stash d'abord." >&2
  exit 1
fi

BUILD="$(git rev-list --count HEAD)"

# 1) Version pubspec (compatible macOS/Linux)
sed -i.bak -E "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml
rm -f pubspec.yaml.bak

# 2) Changelog : section depuis le dernier tag (hors ce tag)
PREV="$(git tag --sort=-creatordate | grep -v "^$TAG$" | head -1 || true)"
RANGE="${PREV:+$PREV..}HEAD"
DATE="$(date +%Y-%m-%d)"
NEW_SECTION="$(mktemp)"
{
  echo "## $TAG - $DATE"
  echo
  git log $RANGE --pretty='- %s' --no-merges
  echo
} > "$NEW_SECTION"

touch CHANGELOG.md
# Retire une éventuelle ancienne section du même tag, puis prépend la nouvelle.
BODY="$(mktemp)"
awk -v tag="## $TAG" '
  $0 ~ "^" tag " " || $0 == tag { skip=1; next }
  skip && /^## / { skip=0 }
  !skip { print }
' CHANGELOG.md > "$BODY"
cat "$NEW_SECTION" "$BODY" > CHANGELOG.md
rm -f "$NEW_SECTION" "$BODY"

# 3) Commit (ignore si rien à committer, ex. re-run)
git add pubspec.yaml CHANGELOG.md
git commit -m "chore(release): $TAG" || echo "Rien de nouveau à committer."

# 4) Tag : supprime l'ancien (local + distant) puis recrée
git tag -d "$TAG" 2>/dev/null || true
git push origin ":refs/tags/$TAG" 2>/dev/null || true
git tag -a "$TAG" -m "$TAG"

# 5) Push branche + tag
git push origin "$BRANCH"
git push origin "$TAG"

echo "✅ Release $TAG poussée (version $VERSION+$BUILD). Le workflow GitHub build les APK."
