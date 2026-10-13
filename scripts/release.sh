#!/usr/bin/env bash
# Cut a release: tag the current main and push the tag. The tag triggers
# .github/workflows/release.yml, which tests, builds, verifies and publishes the .snplg.
#
#   scripts/release.sh v0.2.0            # checks, asks for confirmation, tags and pushes
#   scripts/release.sh v0.2.0 --dry-run  # checks only, changes nothing
#   scripts/release.sh v0.2.0-rc.1       # a pre-release (any "-suffix")
#
# See docs/RELEASING.md.
set -euo pipefail

VERSION=""
DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) [[ -z "$VERSION" ]] || { echo "only one version, please" >&2; exit 2; }; VERSION="$arg" ;;
  esac
done
[[ -n "$VERSION" ]] || { echo "usage: $0 vMAJOR.MINOR.PATCH[-suffix] [--dry-run] [--yes]" >&2; exit 2; }

fail() { echo "error: $*" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"

[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] \
  || fail "'$VERSION' must look like v1.2.3 or v1.2.3-rc.1"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == "main" ]] || fail "releases are cut from main (you are on '$BRANCH')"

[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean; commit or stash first"

git fetch --quiet --tags origin
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse origin/main)"
if [[ "$LOCAL" != "$REMOTE" ]]; then
  if git merge-base --is-ancestor "$REMOTE" "$LOCAL"; then
    fail "main has commits that are not pushed yet ($(git rev-list --count origin/main..HEAD)); push them first, the release builds what is on GitHub"
  else
    fail "main is behind or has diverged from origin/main; pull first"
  fi
fi

git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null && fail "tag $VERSION already exists (versions are never reused)"

PREVIOUS="$(git tag --list 'v[0-9]*' | sort -V | tail -n 1 || true)"
if [[ -n "$PREVIOUS" ]]; then
  [[ "$(printf '%s\n%s\n' "$PREVIOUS" "$VERSION" | sort -V | tail -n 1)" == "$VERSION" ]] \
    || fail "$VERSION is not newer than the latest tag $PREVIOUS"
  [[ "$(git rev-list --count HEAD)" -gt "$(git rev-list --count "$PREVIOUS")" ]] \
    || fail "no commits since $PREVIOUS; nothing to release"
fi

CODE="$(git rev-list --count HEAD)"
echo "Release $VERSION"
echo "  commit       $(git rev-parse --short HEAD)  $(git log -1 --format=%s)"
echo "  versionCode  $CODE"
echo "  previous     ${PREVIOUS:-<none>}"
if [[ -n "$PREVIOUS" ]]; then
  echo "  changes:"
  git log --format='    %h %s' "$PREVIOUS..HEAD" | head -20
fi

echo
[[ -x plugin/node_modules/.bin/tsc && -x plugin/node_modules/.bin/jest && -x plugin/node_modules/.bin/eslint ]] \
  || fail "plugin dependencies are not installed; run: (cd plugin && npm ci)"
echo "Running the quick checks (typecheck, lint, jest)..."
(cd plugin && npx --no-install tsc --noEmit && npx --no-install eslint src App.tsx index.js \
  && npx --no-install jest --ci >/dev/null) || fail "quick checks failed; fix them before releasing"
echo "  ok"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo
  echo "dry run: nothing tagged or pushed."
  exit 0
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo
  read -r -p "Tag $VERSION and push it? This starts the public release build. [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "aborted."; exit 1; }
fi

git tag -a "$VERSION" -m "Insert Screenshot $VERSION"
git push origin "$VERSION"

REPO="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
echo
echo "Pushed $VERSION. Watch the build: https://github.com/$REPO/actions"
echo "The release appears at:           https://github.com/$REPO/releases/tag/$VERSION"
