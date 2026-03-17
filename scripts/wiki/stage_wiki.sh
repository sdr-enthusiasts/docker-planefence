#!/usr/bin/env bash
set -euo pipefail

# Stage wiki source files from docs/wiki into an output directory.
# This script does not publish anything; it only prepares content.

SRC_DIR="${1:-docs/wiki}"
OUT_DIR="${2:-.wiki-dist}"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Source directory not found: $SRC_DIR" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Copy top-level markdown pages only. Template files are intentionally excluded.
find "$SRC_DIR" -maxdepth 1 -type f -name '*.md' -print0 | while IFS= read -r -d '' file; do
  cp "$file" "$OUT_DIR/"
done

echo "Staged wiki content from '$SRC_DIR' to '$OUT_DIR'"
ls -1 "$OUT_DIR" | sed 's/^/- /'
