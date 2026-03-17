#!/usr/bin/env bash
set -euo pipefail

# Publish staged wiki markdown files into the GitHub Wiki repository.
# Requires:
# - GITHUB_TOKEN
# - GITHUB_REPOSITORY in owner/repo format

STAGED_DIR="${1:-.wiki-dist}"
WORK_DIR="${2:-.wiki-repo}"

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required (owner/repo)}"

if [[ ! -d "$STAGED_DIR" ]]; then
  echo "Staged wiki directory not found: $STAGED_DIR" >&2
  exit 1
fi

WIKI_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.wiki.git"

rm -rf "$WORK_DIR"
git clone "$WIKI_URL" "$WORK_DIR"

# Remove existing wiki content (except .git) and replace with freshly staged pages.
find "$WORK_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp "$STAGED_DIR"/*.md "$WORK_DIR"/

pushd "$WORK_DIR" >/dev/null

if [[ -n "$(git status --porcelain)" ]]; then
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add .
  git commit -m "docs(wiki): sync from repository sources"
  git push origin HEAD
  echo "Wiki updated successfully."
else
  echo "No wiki changes to publish."
fi

popd >/dev/null
