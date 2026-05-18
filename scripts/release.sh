#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

YES=0
VERSION=""

for arg in "$@"; do
  case "$arg" in
    -y|--yes)
      YES=1
      ;;
    v[0-9]*|[0-9]*)
      VERSION="${arg#v}"
      ;;
    *)
      echo "Usage: $0 [version] [-y|--yes]"
      echo "Example: $0 1.3.2 --yes"
      exit 2
      ;;
  esac
done

# Get latest version tag
LATEST_TAG=$(git tag --sort=-v:refname | head -1 || true)

if [ -z "$VERSION" ]; then
  if [ -n "$LATEST_TAG" ]; then
    # Auto-bump patch: v1.3.1 -> v1.3.2
    VERSION=$(echo "$LATEST_TAG" | sed 's/^v//' | awk -F. '{$NF+=1; printf "%d.%d.%d", $1, $2, $NF}')
  else
    VERSION="0.1.0"
  fi
fi

TAG="v${VERSION#v}"

echo "=== Release Paozier ${TAG} ==="
echo "Latest tag: ${LATEST_TAG:-none}"

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "ERROR: Tag ${TAG} already exists."
  exit 1
fi

if ! git diff-index --quiet HEAD --; then
  echo "ERROR: Working tree has uncommitted changes. Commit or stash them before releasing."
  exit 1
fi

# Confirm unless --yes passed
if [ "$YES" -ne 1 ]; then
  read -p "Create and push tag ${TAG}? [Y/n] " REPLY
  if [[ ! "$REPLY" =~ ^[Yy]?$ ]]; then
    echo "Cancelled."
    exit 1
  fi
fi

git tag -a "$TAG" -m "Release ${TAG}"
git push origin "$TAG"

echo ""
echo "Tag ${TAG} pushed. GitHub Actions is building the DMG..."
echo "Check: https://github.com/mcxen/paozier/actions"
echo "After build: https://github.com/mcxen/paozier/releases/tag/${TAG}"
