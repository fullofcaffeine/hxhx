#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="$ROOT/test/portable/fixtures"

if [ ! -d "$FIXTURE_ROOT" ]; then
  echo "No portable fixtures directory found at $FIXTURE_ROOT" >&2
  exit 1
fi

if ! command -v "$HAXE_BIN" >/dev/null 2>&1; then
  echo "Missing Haxe compiler on PATH (expected '$HAXE_BIN')." >&2
  exit 1
fi

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping portable conformance: dune/ocamlc not found on PATH."
  exit 0
fi

for dir in "$FIXTURE_ROOT"/*/; do
  [ -f "${dir}build.hxml" ] || continue
  echo "== Portable: ${dir#"$ROOT/"}"

  (
    cd "$dir"
    rm -rf out
    mkdir -p out
    "$HAXE_BIN" build.hxml -D ocaml_build=native
  )

  exe="${dir}out/_build/default/out.exe"
  if [ ! -f "$exe" ]; then
    echo "Missing built executable: $exe" >&2
    exit 1
  fi

  out_tmp="$(mktemp)"
  err_tmp="$(mktemp)"
  env -u HX_TEST_ENV_MISSING_REFLAXE_OCAML HX_TEST_ENV=ok "$exe" >"$out_tmp" 2>"$err_tmp"

  diff -u "${dir}expected.stdout" "$out_tmp"

  if [ -f "${dir}expected.stderr" ]; then
    diff -u "${dir}expected.stderr" "$err_tmp"
  else
    if [ -s "$err_tmp" ]; then
      echo "Unexpected stderr for fixture ${dir#"$ROOT/"}:" >&2
      cat "$err_tmp" >&2
      exit 1
    fi
  fi

  rm -f "$out_tmp" "$err_tmp"
done

echo "✓ Portable conformance OK"

