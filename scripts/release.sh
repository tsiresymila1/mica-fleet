#!/usr/bin/env bash
# Crée une release : bump version pubspec, génère le changelog, commit + tag.
# Usage : ./scripts/release.sh <version>   (ex: ./scripts/release.sh 1.2.0)
# Pousser ensuite : git push origin main && git push origin v<version>
# Le tag déclenche le workflow GitHub qui build l'APK et publie la release.
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

# Garde-fous
if [ -n "$(git status --porcelain)" ]; then
  echo "Arbre de travail non propre — commit/stash d'abord." >&2
  exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Le tag $TAG existe déjà." >&2
  exit 1
fi

BUILD="$(git rev-list --count HEAD)"

# Met à jour la version dans pubspec.yaml (compatible macOS/Linux)
sed -i.bak -E "s/^version: .*/version: $VERSION+$BUILD/" pubspec.yaml
rm -f pubspec.yaml.bak

# Génère le changelog depuis le dernier tag
PREV="$(git describe --tags --abbrev=0 2>/dev/null || true)"
RANGE="${PREV:+$PREV..}HEAD"
DATE="$(date +%Y-%m-%d)"
{
  echo "## $TAG - $DATE"
  echo
  git log $RANGE --pretty='- %s' --no-merges
  echo
} > "CHANGELOG-$TAG.md"

# Prépend dans CHANGELOG.md
touch CHANGELOG.md
cat "CHANGELOG-$TAG.md" CHANGELOG.md > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md

git add pubspec.yaml CHANGELOG.md "CHANGELOG-$TAG.md"
git commit -m "chore(release): $TAG"
git tag -a "$TAG" -m "$TAG"

echo "✅ Release $TAG préparée (version $VERSION+$BUILD)."
echo "Pousse pour déclencher le build :"
echo "  git push origin $(git rev-parse --abbrev-ref HEAD) && git push origin $TAG"
