#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_DIR="$ROOT/test/snapshot"

if [ ! -d "$SNAPSHOT_DIR" ]; then
  echo "No snapshot directory found at $SNAPSHOT_DIR" >&2
  exit 1
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

compile_one() {
  local test_dir="$1"
  local rel
  rel="${test_dir#"$ROOT/"}"

  echo "== Snapshot(update): $rel"

  (
    cd "$test_dir"
    rm -rf out
    "$HAXE_BIN" compile.hxml
  )

  if [ ! -d "$test_dir/out" ]; then
    echo "Missing out/ directory after compile: $test_dir/out" >&2
    exit 1
  fi

  rm -rf "$test_dir/intended"
  mkdir -p "$test_dir/intended"
  cp -R "$test_dir/out/." "$test_dir/intended/"
}

while IFS= read -r -d '' hxml; do
  case "$hxml" in
    */_archive/*) continue ;;
  esac
  compile_one "$(dirname "$hxml")"
done < <(find "$SNAPSHOT_DIR" -name compile.hxml -print0 | sort -z)

echo "✓ Snapshots updated"

