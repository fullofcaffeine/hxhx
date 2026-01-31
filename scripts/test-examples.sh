#!/usr/bin/env bash
set -euo pipefail

HAXE_BIN="${HAXE_BIN:-haxe}"

if ! command -v dune >/dev/null 2>&1 || ! command -v ocamlc >/dev/null 2>&1; then
  echo "Skipping examples: dune/ocamlc not found on PATH."
  exit 0
fi

for dir in examples/*/; do
  [ -f "${dir}build.hxml" ] || continue
  if [ -f "${dir}ACCEPTANCE_ONLY" ]; then
    if [ "${ONLY_ACCEPTANCE_EXAMPLES:-0}" = "1" ]; then
      :
    elif [ "${RUN_ACCEPTANCE_EXAMPLES:-0}" = "1" ]; then
      :
    else
      echo "Skipping acceptance example: ${dir}"
      continue
    fi
  else
    if [ "${ONLY_ACCEPTANCE_EXAMPLES:-0}" = "1" ]; then
      continue
    fi
  fi
  echo "== Example: ${dir}"

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

  tmp="$(mktemp)"
  HX_TEST_ENV=ok "$exe" > "$tmp"
  diff -u "${dir}expected.stdout" "$tmp"
  rm -f "$tmp"
done
