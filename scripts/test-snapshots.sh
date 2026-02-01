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

  echo "== Snapshot: $rel"

  (
    cd "$test_dir"
    rm -rf out
    "$HAXE_BIN" compile.hxml
  )

  if [ ! -d "$test_dir/intended" ]; then
    echo "Missing intended/ directory: $test_dir/intended" >&2
    exit 1
  fi

  diff -ru "$test_dir/intended" "$test_dir/out"

  # Optional sanity check: ensure the generated OCaml parses.
  # This does not typecheck or link the output (which would require external libs),
  # but it catches many printer-level syntax regressions early.
  if command -v ocamlc >/dev/null 2>&1; then
    while IFS= read -r -d '' ml; do
      ocamlc -stop-after parsing -c "$ml" >/dev/null 2>&1 || {
        echo "OCaml parse failed: ${ml#"$ROOT/"}" >&2
        exit 1
      }
    done < <(find "$test_dir/out" -type f -name '*.ml' -print0 | sort -z)
  fi
}

while IFS= read -r -d '' hxml; do
  case "$hxml" in
    */_archive/*) continue ;;
  esac
  compile_one "$(dirname "$hxml")"
done < <(find "$SNAPSHOT_DIR" -name compile.hxml -print0 | sort -z)

echo "✓ Snapshots OK"
