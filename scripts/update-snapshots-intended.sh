#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_DIR="$ROOT/test/snapshot"

if [ ! -d "$SNAPSHOT_DIR" ]; then
  echo "No snapshot directory found at $SNAPSHOT_DIR" >&2
  exit 1
fi

find "$SNAPSHOT_DIR" -type f -name compile.hxml -print0 | while IFS= read -r -d '' hxml; do
  test_dir="$(dirname "$hxml")"
  if [ ! -d "$test_dir/out" ]; then
    echo "Skipping (no out/): ${test_dir#"$ROOT/"}"
    continue
  fi

  rm -rf "$test_dir/intended" 2>/dev/null || true
  cp -R "$test_dir/out" "$test_dir/intended"
  echo "Updated intended/: ${test_dir#"$ROOT/"}"
done

